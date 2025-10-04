import 'dart:io' show Platform, File;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:guardias_escolares/presentation/viewmodels/check_in_view_model.dart';
import 'package:guardias_escolares/presentation/viewmodels/auth_view_model.dart' as auth_vm;
import 'package:guardias_escolares/domain/checkin/entities/check_in.dart';

class CheckInExportPage extends ConsumerStatefulWidget {
  const CheckInExportPage({super.key});

  @override
  ConsumerState<CheckInExportPage> createState() => _CheckInExportPageState();
}

class _CheckInExportPageState extends ConsumerState<CheckInExportPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _loading = false;
  List<CheckIn> _events = [];
  String? _error;
  // Paginación simple: volvemos a pedir con un límite mayor
  final int _pageSize = 1000; // tamaño de incremento
  bool _hasMore = true;
  bool _paging = false;

  Duration get _totalWorked {
    final sessions = _buildSessions(_events);
    Duration acc = Duration.zero;
    for (final s in sessions) {
      if (s.inTs != null && s.outTs != null && s.outTs!.isAfter(s.inTs!)) {
        acc += s.outTs!.difference(s.inTs!);
      }
    }
    return acc;
  }

  Future<void> _pickFrom() async {
    final d = await showDatePicker(context: context, initialDate: _from, firstDate: DateTime(2023), lastDate: DateTime(2100));
    if (d == null) return;
    setState(()=> _from = DateTime(d.year,d.month,d.day));
  }
  Future<void> _pickTo() async {
    final d = await showDatePicker(context: context, initialDate: _to, firstDate: DateTime(2023), lastDate: DateTime(2100));
    if (d == null) return;
    setState(()=> _to = DateTime(d.year,d.month,d.day,23,59,59,999));
  }

  Future<void> _load({bool reset = true}) async {
    final user = ref.read(auth_vm.authViewModelProvider).maybeWhen(authenticated: (u)=>u, orElse: ()=>null);
    if (user == null) return;
    if (reset) {
      setState((){ _loading=true; _error=null; _events=[]; _hasMore=true; });
    } else {
      if (_paging || !_hasMore) return; // evita llamadas concurrentes
      setState(()=> _paging = true);
    }
    try {
      final repo = ref.read(checkInRepositoryProvider);
      final current = reset ? 0 : _events.length;
      final limit = current + _pageSize; // pedimos más que lo ya mostrado
      final list = await repo.fetchUserCheckIns(userId: user.uid, fromUtc: _from.toUtc(), toUtc: _to.toUtc(), limit: limit);
      if (!mounted) return;
      setState((){ 
        _events = list; 
        _loading=false; 
        _paging=false; 
        _hasMore = list.length >= limit; // si llenó el límite asumimos que puede haber más
      });
    } catch(e){
      if (!mounted) return;
      setState((){ _error = e.toString(); _loading=false; _paging=false; });
    }
  }

  String _fmtDate(DateTime d){
    return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  }
  String _fmtTime(DateTime d){
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  List<_Session> _buildSessions(List<CheckIn> raw){
    final byDay = <String,List<CheckIn>>{};
    for(final c in raw){
      final l = c.timestampUtc.toLocal();
      final day = _fmtDate(l);
      byDay.putIfAbsent(day, ()=>[]).add(c);
    }
    final sessions = <_Session>[];
    final sortedDays = byDay.keys.toList()..sort();
    for(final day in sortedDays){
      final evs = byDay[day]!..sort((a,b)=>a.timestampUtc.compareTo(b.timestampUtc));
  DateTime? openIn; final listIds=<String>[]; int inCount=0; int outCount=0;
      for(final ev in evs){
        if(ev.type==CheckInType.inEvent){
          if(openIn!=null){
            sessions.add(_Session(day: day, inTs: openIn, outTs: null, inCount: inCount, outCount: outCount));
            inCount=0; outCount=0; listIds.clear();
          }
          openIn=ev.timestampUtc.toLocal(); inCount++; listIds.add(ev.id);
        } else {
          outCount++;
          if(openIn!=null){
            sessions.add(_Session(day: day, inTs: openIn, outTs: ev.timestampUtc.toLocal(), inCount: inCount, outCount: outCount));
            openIn=null; inCount=0; outCount=0; listIds.clear();
          } else {
            sessions.add(_Session(day: day, inTs: null, outTs: ev.timestampUtc.toLocal(), inCount: 0, outCount: outCount));
            outCount=0;
          }
        }
      }
      if(openIn!=null){
        sessions.add(_Session(day: day, inTs: openIn, outTs: null, inCount: inCount, outCount: outCount));
      }
    }
    return sessions;
  }

  Future<void> _exportPdf() async {
    if(_events.isEmpty) return;
    final sessions = _buildSessions(_events);
    final total = _totalWorked;
    String totalFmt(){
      final h = total.inHours; final m = total.inMinutes % 60; return '${h}h ${m}m';
    }
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx){
          return [
            pw.Text('Reporte personal de check-ins', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Rango: ${_fmtDate(_from)} a ${_fmtDate(_to)}  (Sesiones: ${sessions.length})  Total: ${totalFmt()}', style: pw.TextStyle(fontSize: 11)),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: ['Día','Entrada','Salida','Duración','In','Out'],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
              data: [
                for(final s in sessions) [
                  s.day,
                  s.inTs==null?'':_fmtTime(s.inTs!),
                  s.outTs==null?'':_fmtTime(s.outTs!),
                  (s.inTs!=null && s.outTs!=null && s.outTs!.isAfter(s.inTs!)) ? _humanDuration(s.outTs!.difference(s.inTs!)) : '',
                  s.inCount.toString(),
                  s.outCount.toString(),
                ]
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text('Generado: ${DateTime.now().toLocal()}')
          ];
        }
      )
    );
    final bytes = await doc.save();
  bool attempted=false;
  String? savedPath;
    try{
      if(!Platform.isLinux && !Platform.isWindows){
        await Printing.layoutPdf(onLayout: (f) async => bytes, name: 'reporte_personal_checkins.pdf');
        attempted=true;
      }
    }catch(_){attempted=false;}
    if(!attempted){
      final dir = await getTemporaryDirectory();
      savedPath='${dir.path}/reporte_personal_checkins_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final f = File(savedPath); await f.writeAsBytes(bytes, flush: true);
      if(!mounted) return; ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF guardado: '+savedPath)));
    }
    // Compartir archivo (siempre generamos uno local si impresión directa) 
    try {
      if (attempted) {
        final dir = await getTemporaryDirectory();
        savedPath='${dir.path}/reporte_personal_checkins_share_${DateTime.now().millisecondsSinceEpoch}.pdf';
        final f = File(savedPath); await f.writeAsBytes(bytes, flush: true);
      }
      if (savedPath != null) {
        await Share.shareXFiles([XFile(savedPath)], text: 'Reporte de check-ins');
      }
    } catch (_) {}
  }

  @override
  void initState(){
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Check-ins'),
        actions: [
          IconButton(
            tooltip: 'Exportar a PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _events.isEmpty ? null : _exportPdf,
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(onPressed: _pickFrom, icon: const Icon(Icons.calendar_today), label: Text('Desde ${_fmtDate(_from)}')),
                TextButton.icon(onPressed: _pickTo, icon: const Icon(Icons.calendar_month), label: Text('Hasta ${_fmtDate(_to)}')),
                ElevatedButton.icon(onPressed: _loading ? null : () => _load(reset: true), icon: const Icon(Icons.refresh), label: const Text('Actualizar')),
                FilledButton.icon(onPressed: _events.isEmpty ? null : _exportPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('PDF')),
                FilterChip(
                  label: const Text('Hoy'),
                  selected: false,
                  onSelected: (_){
                    final now = DateTime.now();
                    setState((){ _from = DateTime(now.year,now.month,now.day); _to = DateTime(now.year,now.month,now.day,23,59,59,999); });
                    _load(reset: true);
                  },
                ),
                FilterChip(
                  label: const Text('Semana'),
                  selected: false,
                  onSelected: (_){
                    final now = DateTime.now();
                    final start = now.subtract(Duration(days: now.weekday-1));
                    final end = start.add(const Duration(days:6));
                    setState((){ _from = DateTime(start.year,start.month,start.day); _to = DateTime(end.year,end.month,end.day,23,59,59,999); });
                    _load(reset: true);
                  },
                ),
                FilterChip(
                  label: const Text('Mes'),
                  selected: false,
                  onSelected: (_){
                    final now = DateTime.now();
                    final start = DateTime(now.year, now.month, 1);
                    final end = DateTime(now.year, now.month+1, 0, 23,59,59,999);
                    setState((){ _from = start; _to = end; });
                    _load(reset: true);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            if(!_loading && _error==null)
              Row(children: [
                Icon(Icons.timer_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('Total horas: ' + _formatDuration(_totalWorked), style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                if(_hasMore) TextButton.icon(onPressed: _paging? null : () => _load(reset: false), icon: _paging? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Icon(Icons.expand_more), label: Text(_paging? 'Cargando...' : 'Más')),
              ]),
            const SizedBox(height: 12),
            if(_loading) const LinearProgressIndicator(minHeight: 2) else if(_error!=null) Text(_error!, style: TextStyle(color: cs.error)) else Expanded(
              child: _events.isEmpty ? const Center(child: Text('No hay eventos en el rango.')) : _SessionsList(events: _events, buildSessions: _buildSessions, fmtTime: _fmtTime, fmtDate: _fmtDate),
            )
          ],
        ),
      ),
    );
  }
}

class _SessionsList extends StatelessWidget {
  final List<CheckIn> events;
  final List<_Session> Function(List<CheckIn>) buildSessions;
  final String Function(DateTime) fmtTime;
  final String Function(DateTime) fmtDate;
  const _SessionsList({required this.events, required this.buildSessions, required this.fmtTime, required this.fmtDate});
  @override
  Widget build(BuildContext context) {
    final sessions = buildSessions(events);
    return ListView.separated(
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i){
        final s = sessions[i];
        final cs = Theme.of(context).colorScheme;
        return ListTile(
          dense: true,
          title: Text(s.day),
          subtitle: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if(s.inTs!=null) Text('In ${fmtTime(s.inTs!)}'),
              if(s.outTs!=null) Text('Out ${fmtTime(s.outTs!)}'),
              if(s.inTs!=null && s.outTs!=null && s.outTs!.isAfter(s.inTs!)) Text(_humanDuration(s.outTs!.difference(s.inTs!)), style: TextStyle(color: cs.onSurfaceVariant)),
              Text('(${s.inCount}/${s.outCount})', style: TextStyle(color: cs.outline, fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}

class _Session {
  final String day; final DateTime? inTs; final DateTime? outTs; final int inCount; final int outCount;
  _Session({required this.day, this.inTs, this.outTs, required this.inCount, required this.outCount});
}

String _humanDuration(Duration d){
  final h = d.inHours; final m = d.inMinutes % 60; if(h>0) return '${h}h ${m}m'; return '${m}m';
}

String _formatDuration(Duration d){
  final h = d.inHours; final m = d.inMinutes % 60; return '${h}h ${m}m';
}
