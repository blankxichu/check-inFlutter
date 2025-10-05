import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';

admin.initializeApp();
const db = admin.firestore();

// Utilidad: depurar tokens duplicados entre usuarios y retornar sólo los válidos para un uid.
// Estrategia: para el conjunto de tokens de ese usuario, buscamos duplicados via collectionGroup 'fcmTokens'.
// Elegimos como autoritativo el documento con mayor updatedAt (si existe) y borramos los demás. Si el autoritativo
// pertenece a otro usuario, eliminamos el doc local y NO enviamos a ese token.
async function sanitizeUserTokens(targetUid: string, tokens: string[]): Promise<string[]> {
  // Hotfix flag: desactivar sanitización avanzada para recuperar entregas rápidas
  const ENABLE_TOKEN_SANITIZE = false; // ⚠️ DESACTIVADO: collectionGroup requiere índice que causa FAILED_PRECONDITION
  if (!ENABLE_TOKEN_SANITIZE) {
    return tokens; // skip logic
  }
  if (tokens.length === 0) return [];

  try {
    const MAX_IN = 10; // límite Firestore 'in'
    const chunks: string[][] = [];
    if (tokens.length <= MAX_IN) {
      chunks.push(tokens);
    } else {
      for (let i = 0; i < tokens.length; i += MAX_IN) {
        chunks.push(tokens.slice(i, i + MAX_IN));
      }
    }
    const allDupDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    for (const ch of chunks) {
      try {
        const snap = await db.collectionGroup('fcmTokens').where('token', 'in', ch).get();
        allDupDocs.push(...snap.docs);
      } catch (error) {
        console.error('[sanitizeUserTokens] fallback (query failed)', { targetUid, chunkSize: ch.length, error });
        return tokens; // No arriesgar bloqueo; usar lista original
      }
    }
    // Agrupar por token
    const byToken: Record<string, FirebaseFirestore.QueryDocumentSnapshot[]> = {};
    for (const d of allDupDocs) {
      const tk = (d.get('token') as string) || d.id;
      if (!byToken[tk]) byToken[tk] = [];
      byToken[tk].push(d);
    }
    const valid: string[] = [];
    const now = Date.now();
    for (const tk of tokens) {
      const docs = byToken[tk] || [];
      if (docs.length === 0) {
        // No se encontraron duplicados via collectionGroup (posible inconsistencia si faltó 'token' field); conservar tentativamente
        valid.push(tk);
        continue;
      }
      // Seleccionar doc con updatedAt más reciente
      let best: FirebaseFirestore.QueryDocumentSnapshot | undefined;
      let bestTs = -1;
      for (const doc of docs) {
        const ts = doc.get('updatedAt');
        let ms = 0;
        if (ts && typeof ts.toDate === 'function') {
          ms = ts.toDate().getTime();
        } else {
          // Fallback: usar createTime si no hay updatedAt
          try { ms = doc.createTime.toDate().getTime(); } catch { ms = now - 1000000; }
        }
        if (ms > bestTs) { bestTs = ms; best = doc; }
      }
      if (!best) continue;
      const bestUser = best.ref.parent.parent?.id;
      // Borrar duplicados que no son best
      for (const doc of docs) {
        if (doc.id === best.id) continue;
        try { await doc.ref.delete(); } catch (_) {}
      }
      if (bestUser === targetUid) {
        valid.push(tk);
      } else {
        // El token está más actualizado en otro usuario -> eliminar copia local en targetUid si existe
        try { await db.collection('users').doc(targetUid).collection('fcmTokens').doc(tk).delete(); } catch (_) {}
      }
    }
    if (valid.length === 0 && tokens.length > 0) {
      console.warn('[sanitizeUserTokens] All tokens filtered for', targetUid, 'falling back to original list of', tokens.length);
      return tokens; // fallback defensivo
    }
    return valid;
  } catch (error) {
    console.error('[sanitizeUserTokens] fatal fallback', {
      targetUid,
      tokenCount: tokens.length,
      error,
    });
    return tokens;
  }
}

const INVALID_TOKEN_ERROR_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/unregistered',
]);

type PushErrorDetail = { token: string; code?: string; message?: string };

function analyzeMulticastResult(tokens: string[], res: admin.messaging.BatchResponse) {
  const invalid: string[] = [];
  const otherErrors: PushErrorDetail[] = [];
  res.responses.forEach((response, index) => {
    if (response.success) return;
    const token = tokens[index];
    const code = response.error?.code;
    const message = response.error?.message;
    if (code && INVALID_TOKEN_ERROR_CODES.has(code)) {
      invalid.push(token);
    } else {
      otherErrors.push({ token, code, message });
    }
  });
  return { invalid, otherErrors };
}

async function handleMulticastCleanup(uid: string, tokens: string[], res: admin.messaging.BatchResponse) {
  const { invalid, otherErrors } = analyzeMulticastResult(tokens, res);
  if (invalid.length) {
    const batch = db.batch();
    for (const token of invalid) {
      const ref = db.collection('users').doc(uid).collection('fcmTokens').doc(token);
      batch.delete(ref);
    }
    await batch.commit();
    console.log('[push] Removed invalid tokens for', uid, invalid);
  }
  if (otherErrors.length) {
    console.warn('[push] Non-invalid errors for', uid, otherErrors);
  }
  return {
    success: res.successCount,
    failure: res.failureCount,
    invalidRemoved: invalid.length,
    errors: otherErrors,
  };
}

// Callable to send a test notification to a given uid
export const sendTestNotification = onCall(async (request) => {
  const data = request.data as { uid?: string; title?: string; body?: string };
  const uid = data.uid ?? '';
  const title = data.title ?? 'Prueba';
  const body = data.body ?? 'Mensaje de prueba';
  if (!uid) throw new Error('invalid-argument: uid is required');

  const tokensSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
  let tokens = tokensSnap.docs.map(d => d.id);
  tokens = await sanitizeUserTokens(uid, tokens);
  if (tokens.length === 0) return { sent: 0, failure: 0, invalidRemoved: 0, errors: [] };

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: { title, body },
    data: { body },
  };
  const res = await admin.messaging().sendEachForMulticast(message);
  const summary = await handleMulticastCleanup(uid, tokens, res);
  return { sent: res.successCount, failed: res.failureCount, ...summary };
});

// Callable to set user role via custom claims. Requires caller to be admin OR provide bootstrap secret
export const setUserRole = onCall({ enforceAppCheck: false }, async (request) => {
  const data = request.data as { uid?: string; email?: string; role?: string; secret?: string };
  const role = (data.role || '').toLowerCase();
  if (role !== 'admin' && role !== 'parent') {
    throw new HttpsError('invalid-argument', "role must be 'admin' or 'parent'");
  }

  // Bootstrap secret from env or functions config - check this FIRST for bootstrap flow
  const bootstrapEnv = process.env.ADMIN_BOOTSTRAP_SECRET;
  let bootstrapConfig: string | undefined;
  try {
    // For v6+ functions, use defineSecret or environment variables
    // Legacy functions.config() fallback
    const functions = require('firebase-functions/v1');
    bootstrapConfig = functions.config()?.admin?.bootstrap;
  } catch (_) {
    // ignore if not available
  }
  const bootstrapSecret = bootstrapEnv || bootstrapConfig || 'GE-BOOTSTRAP-123'; // Hardcode fallback for dev
  const provided = (data.secret || '').trim();
  const isBootstrapCall = !!bootstrapSecret && provided === bootstrapSecret;

  // Resolve target user by uid or email
  let targetUid = data.uid;
  if (!targetUid && data.email) {
    try {
      const u = await admin.auth().getUserByEmail(data.email);
      targetUid = u.uid;
    } catch (e) {
      throw new HttpsError('not-found', 'User not found by email');
    }
  }
  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'uid or email is required');
  }

  // Check authorization: either admin user OR bootstrap secret
  const caller = request.auth;
  const callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';

  if (!callerIsAdmin && !isBootstrapCall) {
    throw new HttpsError('permission-denied', `Only admins can set roles. Bootstrap: ${!!bootstrapSecret}, provided: ${provided}`);
  }

  await admin.auth().setCustomUserClaims(targetUid, { role });
  await db.collection('users').doc(targetUid).set({ role }, { merge: true });
  return { ok: true, uid: targetUid, role, method: isBootstrapCall ? 'bootstrap' : 'admin' };
});

// Scheduled reminder: send reminder at 18:00 UTC one day before a shift
export const scheduledShiftReminders = onSchedule('0 18 * * *', async (event) => {
  const now = new Date();
  const target = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
  const dayId = target.toISOString().substring(0, 10);
  const shiftRef = db.collection('shifts').doc(dayId);
  const snap = await shiftRef.get();
  if (!snap.exists) return null;
  const data = snap.data() as any;
  const users: string[] = data.users ?? [];
  if (users.length === 0) return null;

  // For each user, collect tokens and send a reminder
  const tokenBatches: Array<{ uid: string; tokens: string[] }> = [];
  for (const uid of users) {
    const tSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
    let t = tSnap.docs.map(d => d.id);
    t = await sanitizeUserTokens(uid, t);
    if (t.length) tokenBatches.push({ uid, tokens: t });
  }
  if (tokenBatches.length === 0) return null;

  const title = 'Recordatorio de guardia';
  const body = `Mañana tienes guardia (${dayId}).`;

  // Send in batches to respect FCM limits
  for (const target of tokenBatches) {
    const { uid, tokens } = target;
    const msg: admin.messaging.MulticastMessage = {
      tokens,
      notification: { title, body },
      data: { body },
    };
    const res = await admin.messaging().sendEachForMulticast(msg);
    await handleMulticastCleanup(uid, tokens, res);
  }
  return null;
});

// ---------------------------------------------------------------------------
// Limpieza de tokens FCM antiguos
// Elimina documentos en subcolección users/*/fcmTokens con updatedAt < ahora - 60 días
// Se ejecuta diariamente a las 03:10 UTC para minimizar impacto.
// ---------------------------------------------------------------------------
export const cleanupOldFcmTokens = onSchedule('10 3 * * *', async () => {
  const DAYS = 60;
  const now = Date.now();
  const cutoffMillis = now - DAYS * 24 * 60 * 60 * 1000;
  const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMillis);

  const batchSize = 400; // límite de borrados por iteración para no exceder quotas
  let deleted = 0;
  // collectionGroup para recorrer todos los subdocs 'fcmTokens'
  const snap = await db.collectionGroup('fcmTokens')
    .where('updatedAt', '<', cutoff)
    .get();

  if (snap.empty) {
    console.log('cleanupOldFcmTokens: nothing to delete');
    return;
  }

  let batch = db.batch();
  let ops = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
    ops++; deleted++;
    if (ops >= batchSize) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }
  if (ops > 0) {
    await batch.commit();
  }
  console.log('cleanupOldFcmTokens done', { deleted, checked: snap.size, cutoff: cutoff.toDate().toISOString() });
});

// Callable manual para probar limpieza sin esperar al cron
export const cleanupOldFcmTokensNow = onCall(async () => {
  const DAYS = 60;
  const now = Date.now();
  const cutoffMillis = now - DAYS * 24 * 60 * 60 * 1000;
  const cutoff = admin.firestore.Timestamp.fromMillis(cutoffMillis);
  const snap = await db.collectionGroup('fcmTokens')
    .where('updatedAt', '<', cutoff)
    .limit(1000) // safety
    .get();
  if (snap.empty) return { deleted: 0, checked: 0 };
  let batch = db.batch();
  let ops = 0; let deleted = 0;
  for (const d of snap.docs) {
    batch.delete(d.ref); ops++; deleted++;
    if (ops === 400) { await batch.commit(); batch = db.batch(); ops = 0; }
  }
  if (ops > 0) await batch.commit();
  return { deleted, checked: snap.size, cutoff: cutoff.toDate().toISOString() };
});

// ---------------------------------------------------------------------------
// Migración: generar photoUrl para usuarios que sólo tengan avatarPath
// Uso: callable invocado desde un admin (o bootstrap) que recorre bloques de usuarios.
// data: { batch?: number, size?: number }
// Retorna: { processed, updated }
// ---------------------------------------------------------------------------
export const migrateAvatarPhotoUrls = onCall(async (request) => {
  const caller = request.auth;
  const callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';
  if (!callerIsAdmin) {
    throw new HttpsError('permission-denied', 'Sólo admin');
  }
  const data = request.data as { batch?: number; size?: number };
  const batchIndex = data.batch ?? 0;
  const size = Math.min(Math.max(data.size ?? 50, 1), 200);
  const usersSnap = await db.collection('users')
    .orderBy(admin.firestore.FieldPath.documentId())
    .offset(batchIndex * size)
    .limit(size)
    .get();
  if (usersSnap.empty) return { processed: 0, updated: 0, done: true };
  let updated = 0;
  for (const doc of usersSnap.docs) {
    const d = doc.data() as any;
    if (d.photoUrl || !d.avatarPath) continue; // ya tiene o no aplica
    try {
      const fileRef = admin.storage().bucket().file(d.avatarPath);
      const [url] = await fileRef.getSignedUrl({ action: 'read', expires: Date.now() + 1000 * 60 * 60 * 24 * 30 }); // 30 días
      await doc.ref.set({ photoUrl: url }, { merge: true });
      updated++;
    } catch (e) {
      console.warn('migrateAvatarPhotoUrls error', doc.id, e);
    }
  }
  return { processed: usersSnap.size, updated, done: usersSnap.size < size };
});

// Callable para asignar o quitar una guardia a un usuario (solo admin)
// data: { uid?: string; email?: string; day?: string | number; action?: 'assign' | 'unassign'; capacity?: number }
export const assignShift = onCall({ enforceAppCheck: false }, async (request) => {
  const data = request.data as { uid?: string; email?: string; day?: string | number; action?: string; capacity?: number; start?: string; end?: string };
  const action = (data.action || 'assign').toLowerCase();
  if (action !== 'assign' && action !== 'unassign') {
    throw new HttpsError('invalid-argument', "action must be 'assign' or 'unassign'");
  }

  // Auth: requiere admin
  const caller = request.auth;
  const callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';
  if (!callerIsAdmin) {
    throw new HttpsError('permission-denied', 'Solo administradores pueden asignar guardias');
  }

  // Resolver usuario objetivo por uid o email
  let targetUid = data.uid;
  if (!targetUid && data.email) {
    try {
      const u = await admin.auth().getUserByEmail(data.email);
      targetUid = u.uid;
    } catch (e) {
      throw new HttpsError('not-found', 'Usuario no encontrado por email');
    }
  }
  if (!targetUid) {
    throw new HttpsError('invalid-argument', 'uid o email es requerido');
  }

  // Calcular dayId en UTC (yyyy-MM-dd)
  let date: Date;
  if (typeof data.day === 'number') {
    date = new Date(data.day);
  } else if (typeof data.day === 'string') {
    // Permitir 'yyyy-MM-dd' o ISO
    const s = data.day.length === 10 ? `${data.day}T00:00:00.000Z` : data.day;
    const parsed = new Date(s);
    if (isNaN(parsed.getTime())) {
      throw new HttpsError('invalid-argument', 'Formato de fecha inválido');
    }
    date = parsed;
  } else {
    throw new HttpsError('invalid-argument', 'day es requerido');
  }
  const utc = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const dayId = utc.toISOString().substring(0, 10);

  const ref = db.collection('shifts').doc(dayId);
  // Parse various time inputs to minutes from midnight (0..1439)
  const parseToMinutes = (input?: string): number | undefined => {
    if (!input) return undefined;
    let s = String(input).trim().toLowerCase();
    s = s.replace(/\./g, ':').replace(/\s+/g, ' ').trim();
    let m = /^(\d{1,2}):(\d{2})\s*(am|pm)$/.exec(s);
    if (m) {
      let h = parseInt(m[1], 10);
      const min = parseInt(m[2], 10);
      const ap = m[3];
      if (ap === 'pm' && h < 12) h += 12;
      if (ap === 'am' && h === 12) h = 0;
      return h * 60 + min;
    }
    m = /^(\d{1,2})\s*(am|pm)$/.exec(s);
    if (m) {
      let h = parseInt(m[1], 10);
      const ap = m[2];
      if (ap === 'pm' && h < 12) h += 12;
      if (ap === 'am' && h === 12) h = 0;
      return h * 60;
    }
    m = /^(\d{1,2})(am|pm)$/.exec(s);
    if (m) {
      let h = parseInt(m[1], 10);
      const ap = m[2];
      if (ap === 'pm' && h < 12) h += 12;
      if (ap === 'am' && h === 12) h = 0;
      return h * 60;
    }
    m = /^(\d{1,2}):(\d{2})$/.exec(s);
    if (m) {
      const h = parseInt(m[1], 10);
      const min = parseInt(m[2], 10);
      return h * 60 + min;
    }
    return undefined;
  };
  const minutesToHHmm = (min: number): string => {
    const h = Math.floor(min / 60);
    const m = min % 60;
    const two = (v: number) => v.toString().padStart(2, '0');
    return `${two(h)}:${two(m)}`;
  };
  const startMin = parseToMinutes(data.start);
  const endMin = parseToMinutes(data.end);
  let userWasAdded = false; // para saber si debemos notificar
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const exists = snap.exists;
    const dataDoc = (exists ? snap.data() : undefined) as any | undefined;
  const users: string[] = Array.isArray(dataDoc?.users) ? [...dataDoc!.users] : [];
  const capacity = typeof data.capacity === 'number' ? data.capacity : (typeof dataDoc?.capacity === 'number' ? dataDoc!.capacity : 2);
  const slots: Record<string, any> = typeof dataDoc?.slots === 'object' && dataDoc!.slots ? { ...dataDoc!.slots } : {};

    if (action === 'assign') {
      if (!users.includes(targetUid!)) {
        if (users.length >= capacity) {
          throw new HttpsError('failed-precondition', 'El día alcanzó la capacidad máxima');
        }

        // (normalizedSearch helpers moved to bottom of file)

        users.push(targetUid!);
        userWasAdded = true;
      }
      if (typeof startMin === 'number' && typeof endMin === 'number') {
        if (startMin >= endMin) {
          throw new HttpsError('invalid-argument', 'La hora de inicio debe ser menor que la hora de fin');
        }

        let current = slots[targetUid!];
        // Normalizar formato legacy: objeto con Timestamps -> array de objetos {start:'HH:mm', end:'HH:mm'}
        const normMinutes = (v: any): number | undefined => {
          if (!v) return undefined;
          if (typeof v === 'string') {
            const mm = parseToMinutes(v);
            return typeof mm === 'number' ? mm : undefined;
          }
            if (typeof v.toDate === 'function') {
              const d: Date = v.toDate();
              return d.getUTCHours() * 60 + d.getUTCMinutes();
            }
            if (v instanceof Date) {
              return v.getUTCHours() * 60 + v.getUTCMinutes();
            }
            return undefined;
        };
        if (current && !Array.isArray(current) && typeof current === 'object' && current.start && current.end) {
          const s0 = normMinutes(current.start);
          const e0 = normMinutes(current.end);
          if (typeof s0 === 'number' && typeof e0 === 'number') {
            current = [{ start: minutesToHHmm(s0), end: minutesToHHmm(e0) }];
            slots[targetUid!] = current; // persist normalized immediately
          }
        }
        const toMin = (v: any): number | undefined => {
          if (!v) return undefined;
          if (typeof v === 'string') {
            const mm = parseToMinutes(v);
            return typeof mm === 'number' ? mm : undefined;
          }
          // Firestore Timestamp from Admin SDK
          if (typeof v.toDate === 'function') {
            const d: Date = v.toDate();
            return d.getUTCHours() * 60 + d.getUTCMinutes();
          }
          if (v instanceof Date) {
            return v.getUTCHours() * 60 + v.getUTCMinutes();
          }
          return undefined;
        };

        // Build existing ranges in minutes
        let existing: Array<{ start: number; end: number }> = [];
        if (Array.isArray(current)) {
          existing = current
            .map((item) => ({ start: toMin(item?.start), end: toMin(item?.end) }))
            .filter((x) => typeof x.start === 'number' && typeof x.end === 'number') as Array<{ start: number; end: number }>;
        } else if (current && typeof current === 'object') {
          const s0 = toMin(current.start);
          const e0 = toMin(current.end);
          if (typeof s0 === 'number' && typeof e0 === 'number') {
            existing = [{ start: s0, end: e0 }];
          }
        }

        // Overlap check
        for (const r of existing) {
          if (startMin < r.end && endMin > r.start) {
            const fmt = (x: number) => minutesToHHmm(x);
            throw new HttpsError('invalid-argument', `El horario ${fmt(startMin)}-${fmt(endMin)} se solapa con ${fmt(r.start)}-${fmt(r.end)}`);
          }
        }

        // Normalize existing to HH:mm strings and append new range
        const existingStr = existing.map((r) => ({ start: minutesToHHmm(r.start), end: minutesToHHmm(r.end) }));
        const added = { start: minutesToHHmm(startMin), end: minutesToHHmm(endMin) };

        if (Array.isArray(current)) {
          slots[targetUid!] = [...existingStr, added];
        } else if (current && typeof current === 'object') {
          slots[targetUid!] = [...existingStr, added];
        } else {
          slots[targetUid!] = [added];
        }
      }
    } else {
      // unassign
      const idx = users.indexOf(targetUid!);
      if (idx >= 0) users.splice(idx, 1);
      delete slots[targetUid!];
    }

    const payload: any = { date: utc, users, capacity, slots };
    tx.set(ref, payload, { merge: true });
  });
  // Enviar notificación push si se asignó (y realmente se agregó el usuario)
  // Notificamos siempre que action == assign (aunque ya estuviera) para evitar confusiones si se agregan horarios nuevos.
  if (action === 'assign') {
    try {
      const tokensSnap = await db.collection('users').doc(targetUid!).collection('fcmTokens').get();
      let tokens = tokensSnap.docs.map(d => d.id);
      tokens = await sanitizeUserTokens(targetUid!, tokens);
      if (tokens.length) {
        const timeSummary = (typeof startMin === 'number' && typeof endMin === 'number')
          ? ` (${minutesToHHmm(startMin)}-${minutesToHHmm(endMin)})`
          : '';
        const body = `Tienes guardia el ${dayId}${timeSummary}`;
        console.log('[assignShift] Sending to user', targetUid, 'tokens:', tokens.length, 'day:', dayId);
        const msg: admin.messaging.MulticastMessage = {
          tokens,
          notification: {
            title: 'Nueva guardia asignada',
            body,
          },
          data: {
            type: 'shift',
            day: dayId,
            body,
          },
        };
        const res = await admin.messaging().sendEachForMulticast(msg);
        const summary = await handleMulticastCleanup(targetUid!, tokens, res);
        console.log('[assignShift] result', summary);
        return { ok: true, uid: targetUid, dayId, action, start: typeof startMin === 'number' ? minutesToHHmm(startMin) : undefined, end: typeof endMin === 'number' ? minutesToHHmm(endMin) : undefined, notified: action === 'assign', push: summary };
      } else {
        console.log('[assignShift] No tokens for user', targetUid, 'day:', dayId);
      }
    } catch (e) {
      console.error('Error enviando notificación assignShift', e);
    }
  }
  return { ok: true, uid: targetUid, dayId, action, start: typeof startMin === 'number' ? minutesToHHmm(startMin) : undefined, end: typeof endMin === 'number' ? minutesToHHmm(endMin) : undefined, notified: action === 'assign', push: { success: 0, failure: 0, invalidRemoved: 0, errors: [] } };
});

// ---------------------------------------------------------------------------
// USERS: normalizedSearch helper & migration (para búsqueda por prefijo)
// Campo derivado = (displayName|name + ' ' + email) -> lower, espacios colapsados.
// ---------------------------------------------------------------------------
function buildNormalizedSearch(data: FirebaseFirestore.DocumentData | undefined): string | null {
  if (!data) return null;
  const email = (data.email || '').toString();
  const name = (data.displayName || data.name || '').toString();
  if (!email && !name) return null;
  const raw = `${name} ${email}`.toLowerCase().replace(/\s+/g, ' ').trim();
  return raw || null;
}

export const normalizeUserSearch = onDocumentWritten('users/{userId}', async (event) => {
  const after = event.data?.after;
  if (!after) return; // deleted
  const data = after.data();
  if (!data) return;
  const desired = buildNormalizedSearch(data);
  const current = data.normalizedSearch as string | undefined;
  if (desired && desired !== current) {
    await after.ref.set({ normalizedSearch: desired }, { merge: true });
  }
});

export const migrateNormalizedSearchUsers = onCall(async () => {
  const pageSize = 300;
  let updated = 0;
  let examined = 0;
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let q = db.collection('users').orderBy(admin.firestore.FieldPath.documentId());
    if (cursor) q = q.startAfter(cursor);
    const snap = await q.limit(pageSize).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) {
      examined++;
      const data = doc.data();
      const desired = buildNormalizedSearch(data);
      const current = data.normalizedSearch as string | undefined;
      if (desired && desired !== current) {
        batch.set(doc.ref, { normalizedSearch: desired }, { merge: true });
        updated++;
      }
    }
    if (updated > 0) await batch.commit();
    cursor = snap.docs[snap.docs.length - 1];
    if (snap.size < pageSize) break; // última página
  }
  return { ok: true, examined, updated };
});

// Nueva callable: asignar varios turnos en una sola operación atómica.
// data: { uid?|email?, day: 'yyyy-MM-dd', shifts: [{start:'HH:mm', end:'HH:mm'}], capacity?: number }
export const assignMultipleShifts = onCall({ enforceAppCheck: false }, async (request) => {
  const data = request.data as { uid?: string; email?: string; day?: string; shifts?: Array<{start:string; end:string}>; capacity?: number };
  const caller = request.auth;
  const callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';
  if (!callerIsAdmin) throw new HttpsError('permission-denied', 'Solo administradores');
  if (!data.day) throw new HttpsError('invalid-argument', 'day requerido');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(data.day)) throw new HttpsError('invalid-argument', 'day formato yyyy-MM-dd');
  let targetUid = data.uid;
  if (!targetUid && data.email) {
    try { const u = await admin.auth().getUserByEmail(data.email); targetUid = u.uid; } catch (_) { throw new HttpsError('not-found','Usuario no encontrado'); }
  }
  if (!targetUid) throw new HttpsError('invalid-argument', 'uid o email requerido');

  const rawShifts = Array.isArray(data.shifts) ? data.shifts : [];
  if (rawShifts.length === 0) throw new HttpsError('invalid-argument', 'shifts vacío');

  const parseToMinutes = (s: string): number => {
    let v = s.trim();
    const m = /^(\d{1,2}):(\d{2})$/.exec(v);
    if (!m) throw new HttpsError('invalid-argument', `Formato inválido ${s}`);
    const h = parseInt(m[1],10); const mm = parseInt(m[2],10);
    if (h<0||h>23||mm<0||mm>59) throw new HttpsError('invalid-argument', `Hora fuera de rango ${s}`);
    return h*60+mm;
  };
  const mmTo = (m:number)=>`${String(Math.floor(m/60)).padStart(2,'0')}:${String(m%60).padStart(2,'0')}`;
  type Range = {start:number; end:number};
  const ranges: Range[] = rawShifts.map(r=>({start:parseToMinutes(r.start), end:parseToMinutes(r.end)}));
  for (const r of ranges) if (r.start>=r.end) throw new HttpsError('invalid-argument','Inicio debe ser menor que fin');
  // Ordenar y verificar solapes
  ranges.sort((a,b)=>a.start-b.start);
  for (let i=1;i<ranges.length;i++) if (ranges[i].start < ranges[i-1].end) throw new HttpsError('invalid-argument','Turnos se solapan');

  const dateParts = data.day.split('-');
  const utc = new Date(Date.UTC(parseInt(dateParts[0]), parseInt(dateParts[1])-1, parseInt(dateParts[2])));
  const ref = db.collection('shifts').doc(data.day);
  let userWasAdded = false;
  await db.runTransaction(async tx => {
    const snap = await tx.get(ref);
    const doc = (snap.exists ? snap.data(): {}) as any;
    const users: string[] = Array.isArray(doc?.users)? [...doc.users]: [];
    const capacity = typeof data.capacity === 'number' ? data.capacity : (typeof doc?.capacity === 'number'? doc.capacity : 2);
    const slots = typeof doc?.slots === 'object' && doc.slots ? {...doc.slots}: {};
    if (!users.includes(targetUid!)) {
      if (users.length >= capacity) throw new HttpsError('failed-precondition','Capacidad llena');
      users.push(targetUid!);
      userWasAdded = true;
    }
    slots[targetUid!] = ranges.map(r=>({start:mmTo(r.start), end:mmTo(r.end)}));
    tx.set(ref, { date: utc, users, capacity, slots }, { merge: true });
  });
  // Notificación: solo si es nuevo en el día (userWasAdded)
  if (true) { // siempre notificar al asignar múltiples turnos
    try {
      const tokensSnap = await db.collection('users').doc(targetUid!).collection('fcmTokens').get();
      let tokens = tokensSnap.docs.map(d => d.id);
      tokens = await sanitizeUserTokens(targetUid!, tokens);
      if (tokens.length) {
        const shiftsLabel = ranges.map(r => `${mmTo(r.start)}-${mmTo(r.end)}`).join(', ');
        const body = `Tienes guardias el ${data.day}: ${shiftsLabel}`;
        console.log('[assignMultipleShifts] Sending to user', targetUid, 'tokens:', tokens.length, 'day:', data.day, 'ranges:', shiftsLabel);
        const msg: admin.messaging.MulticastMessage = {
          tokens,
          notification: { title: 'Nueva guardia asignada', body },
          data: { type: 'shift', day: data.day, body },
        };
        const res = await admin.messaging().sendEachForMulticast(msg);
        const summary = await handleMulticastCleanup(targetUid!, tokens, res);
        console.log('[assignMultipleShifts] result', summary);
        return { ok:true, uid: targetUid, dayId: data.day, count: ranges.length, notified: true, push: summary };
      } else {
        console.log('[assignMultipleShifts] No tokens for user', targetUid, 'day:', data.day);
      }
    } catch (e) {
      console.error('Error enviando notificación assignMultipleShifts', e);
    }
  }
  return { ok:true, uid: targetUid, dayId: data.day, count: ranges.length, notified: true, push: { success: 0, failure: 0, invalidRemoved: 0, errors: [] } };
});

// Nueva callable: asignar mismos turnos en MULTIPLES días con UNA sola notificación.
// data: { uid?|email?, days: ['yyyy-MM-dd', ...], shifts: [{start:'HH:mm', end:'HH:mm'}], capacity?: number }

// Callable para normalizar un documento (migración manual): convierte slots legacy (objeto con Timestamps) a array de strings HH:mm
export const normalizeShiftDoc = onCall({ enforceAppCheck: false }, async (request) => {
  const data = request.data as { day: string };
  const caller = request.auth;
  const callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';
  if (!callerIsAdmin) throw new HttpsError('permission-denied', 'Solo administradores');
  const day = data.day;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new HttpsError('invalid-argument', 'Formato day debe ser yyyy-MM-dd');
  const ref = db.collection('shifts').doc(day);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const doc = snap.data() as any;
    const slots = typeof doc?.slots === 'object' && doc.slots ? { ...doc.slots } : {};
    let changed = false;
    const minutesToHHmm = (min: number): string => {
      const h = Math.floor(min / 60); const m = min % 60; const two = (v: number) => v.toString().padStart(2,'0');
      return `${two(h)}:${two(m)}`;
    };
    const toMin = (v: any): number | undefined => {
      if (!v) return undefined;
      if (typeof v === 'string') { const m = parseInt(v.split(':')[0]); const mm = parseInt(v.split(':')[1]); if (!isNaN(m) && !isNaN(mm)) return m*60+mm; }
      if (typeof v.toDate === 'function') { const d: Date = v.toDate(); return d.getUTCHours()*60 + d.getUTCMinutes(); }
      if (v instanceof Date) return v.getUTCHours()*60 + v.getUTCMinutes();
      return undefined;
    };
    Object.keys(slots).forEach(uid => {
      const cur = slots[uid];
      if (cur && !Array.isArray(cur) && typeof cur === 'object' && cur.start && cur.end) {
        const s0 = toMin(cur.start); const e0 = toMin(cur.end);
        if (typeof s0 === 'number' && typeof e0 === 'number') {
          slots[uid] = [{ start: minutesToHHmm(s0), end: minutesToHHmm(e0) }];
          changed = true;
        }
      }
    });
    if (changed) {
      tx.set(ref, { slots }, { merge: true });
    }
  });
  return { ok: true, day };
});

// Callable: Obtener días asignados a un usuario (por uid o email) para un mes específico
// data: { uid?: string; email?: string; year: number; month: number }
export const getAssignedDaysForUserMonth = onCall({ enforceAppCheck: false }, async (request) => {
  const data = request.data as { uid?: string; email?: string; year?: number; month?: number };
  // Auth: requiere admin
  const caller = request.auth;
  let callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';
  if (!callerIsAdmin) {
    // Fallback: verificar en colección users si el caller tiene role=admin
    const callerUid = caller?.uid;
    if (callerUid) {
      try {
        const callerDoc = await db.collection('users').doc(callerUid).get();
        const role = (callerDoc.data() as any)?.role;
        callerIsAdmin = role === 'admin';
      } catch (_) {
        callerIsAdmin = false;
      }
    }
  }
  if (!callerIsAdmin) throw new HttpsError('permission-denied', 'Solo administradores');

  let targetUid = data.uid;
  if (!targetUid && data.email) {
    try {
      const u = await admin.auth().getUserByEmail(data.email);
      targetUid = u.uid;
    } catch (e) {
      throw new HttpsError('not-found', 'Usuario no encontrado por email');
    }
  }
  if (!targetUid) throw new HttpsError('invalid-argument', 'uid o email es requerido');

  const now = new Date();
  const year = typeof data.year === 'number' ? data.year : now.getUTCFullYear();
  const month = typeof data.month === 'number' ? data.month : (now.getUTCMonth() + 1);
  // start: UTC yyyy-mm-01, end: UTC yyyy-mm-last
  const start = new Date(Date.UTC(year, month - 1, 1));
  const end = new Date(Date.UTC(year, month, 0));

  const snap = await db
    .collection('shifts')
    .where('date', '>=', start)
    .where('date', '<=', end)
    .get();

  const days: string[] = [];
  for (const d of snap.docs) {
    const doc = d.data() as any;
    const users: string[] = Array.isArray(doc?.users) ? doc.users : [];
    if (!users.includes(targetUid)) continue;
    const dt: admin.firestore.Timestamp | any = doc.date;
    if (dt && typeof dt.toDate === 'function') {
      const u = dt.toDate() as Date;
      const id = new Date(Date.UTC(u.getUTCFullYear(), u.getUTCMonth(), u.getUTCDate())).toISOString().substring(0, 10);
      days.push(id);
    } else {
      const id = d.id;
      if (/^\d{4}-\d{2}-\d{2}$/.test(id)) days.push(id);
    }
  }
  return { uid: targetUid, year, month, days };
});

// ---------------------------------------------------------------------------
// CHAT: onMessageCreate trigger (Bloque A)
// Estructura esperada:
// chats/{chatId}
//   participants: [uidA, uidB, ...]
//   lastMessage: { text, senderId, createdAt }
//   updatedAt: Timestamp
//   createdAt: Timestamp (en creación inicial)
//   unread: { uidA: number, uidB: number, ... }
// chats/{chatId}/messages/{messageId}
//   senderId: string
//   text: string
//   createdAt: Timestamp
//   readBy: { uid: Timestamp } (opcional)
//   status: 'sent'
// Reglas (Bloque B) controlarán que solo participantes escriban.
// Esta función:
// 1. Actualiza lastMessage y updatedAt del chat.
// 2. Incrementa contadores de unread para otros participantes.
// 3. Envía push notification a los demás participantes.
// NOTA: No modifica lógica existente de shifts.
// ---------------------------------------------------------------------------
export const onChatMessageCreate = onDocumentCreated('chats/{chatId}/messages/{messageId}', async (event) => {
  const snap = event.data;
  if (!snap) return;
  const messageData = snap.data() as any;
  const chatRef = snap.ref.parent.parent; // chats/{chatId}
  if (!chatRef) return;
  const senderId: string = messageData.senderId;
  const text: string = (messageData.text ?? '').toString();
  const createdAt = messageData.createdAt || admin.firestore.FieldValue.serverTimestamp();

  // Fetch chat doc (may not exist if not pre-created)
  const chatSnap = await chatRef.get();
  if (!chatSnap.exists) {
    // Abort quietly - enforce creation beforehand to know participants
    console.warn('[onChatMessageCreate] Chat doc missing for', chatRef.id);
    return;
  }
  const chatData = chatSnap.data() as any;
  const participants: string[] = Array.isArray(chatData.participants) ? chatData.participants : [];
  if (!participants.includes(senderId)) {
    console.warn('[onChatMessageCreate] Sender not in participants', senderId, chatRef.id);
    return;
  }
  // Update unread counts and lastMessage atomically
  const unread: Record<string, number> = typeof chatData.unread === 'object' && chatData.unread ? { ...chatData.unread } : {};
  for (const uid of participants) {
    if (uid === senderId) continue;
    unread[uid] = (unread[uid] ?? 0) + 1;
  }
  const lastMessage = {
    text: text.substring(0, 500), // limitar tamaño para índice
    senderId,
    createdAt: createdAt,
  };
  try {
    // Asegurar readBy para el remitente inmediatamente
    try {
      await snap.ref.set({
        readBy: { [senderId]: admin.firestore.FieldValue.serverTimestamp() },
      }, { merge: true });
    } catch (e) {
      console.warn('[onChatMessageCreate] no se pudo set readBy inicial', e);
    }
    await chatRef.set({
      lastMessage,
      unread,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: chatData.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
  } catch (e) {
    console.error('[onChatMessageCreate] Error updating chat metadata', e);
  }

  // Push notifications to other participants
  try {
    for (const uid of participants) {
      if (uid === senderId) continue;
      const tokensSnap = await db.collection('users').doc(uid).collection('fcmTokens').get();
      let tokens = tokensSnap.docs.map(d => d.id);
      tokens = await sanitizeUserTokens(uid, tokens);
      if (!tokens.length) continue;
      const body = text.length > 120 ? text.substring(0, 117) + '...' : text;
      const msg: admin.messaging.MulticastMessage = {
        tokens,
        notification: { title: 'Nuevo mensaje', body },
        data: {
          type: 'chat',
          chatId: chatRef.id,
          senderId,
          body,
        },
      };
      const res = await admin.messaging().sendEachForMulticast(msg);
      const summary = await handleMulticastCleanup(uid, tokens, res);
      console.log('[onChatMessageCreate] sent to', uid, summary);
    }
  } catch (e) {
    console.error('[onChatMessageCreate] push error', e);
  }
});

// ---------------------------------------------------------------------------
// Migración: eliminar campo 'uid' redundante de fcmTokens existentes
// Uso: callable invocado desde admin para optimizar documentos antiguos
// data: { dryRun?: boolean, batchSize?: number }
// Retorna: { scanned, cleaned, skipped }
// ---------------------------------------------------------------------------
export const cleanupTokensRedundantUid = onCall(async (request) => {
  const caller = request.auth;
  const callerIsAdmin = !!caller && (caller.token as any)?.role === 'admin';
  if (!callerIsAdmin) {
    throw new HttpsError('permission-denied', 'Sólo admin puede ejecutar esta migración');
  }

  const { dryRun = false, batchSize = 500 } = request.data as { dryRun?: boolean; batchSize?: number };
  
  console.log(`[cleanupTokensRedundantUid] Iniciando migración - dryRun=${dryRun}, batchSize=${batchSize}`);
  
  let scanned = 0;
  let cleaned = 0;
  let skipped = 0;

  try {
    const usersSnap = await db.collection('users').get();
    
    for (const userDoc of usersSnap.docs) {
      const tokensSnap = await userDoc.ref.collection('fcmTokens').limit(batchSize).get();
      
      if (tokensSnap.empty) continue;
      
      const batch = db.batch();
      let batchOps = 0;

      for (const tokenDoc of tokensSnap.docs) {
        scanned++;
        const data = tokenDoc.data();
        
        // Si tiene el campo 'uid', eliminarlo
        if (data.uid !== undefined) {
          if (!dryRun) {
            batch.update(tokenDoc.ref, { 
              uid: admin.firestore.FieldValue.delete() 
            });
            batchOps++;
          }
          cleaned++;
        } else {
          skipped++;
        }
      }

      // Ejecutar batch si hay operaciones
      if (!dryRun && batchOps > 0) {
        await batch.commit();
        console.log(`[cleanupTokensRedundantUid] Usuario ${userDoc.id}: ${batchOps} tokens limpiados`);
      }
    }

    const result = {
      scanned,
      cleaned,
      skipped,
      dryRun,
      estimatedSavingsBytes: cleaned * 20, // ~20 bytes por campo uid eliminado
    };

    console.log('[cleanupTokensRedundantUid] Completado:', result);
    return result;

  } catch (error) {
    console.error('[cleanupTokensRedundantUid] Error:', error);
    throw new HttpsError('internal', `Error durante migración: ${error}`);
  }
});
