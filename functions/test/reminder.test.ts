import * as admin from 'firebase-admin';

// Very light test that index compiles and admin is available
describe('functions bootstrap', () => {
  it('admin initialized', () => {
    expect(admin).toBeDefined();
  });
});
