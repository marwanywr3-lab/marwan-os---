import test from 'node:test';import assert from 'node:assert/strict';
import {esc,dayKey,toInput,toISO,occurs,conflicts,progress} from '../assets/domain.js';
test('HTML escaping prevents injected markup',()=>assert.equal(esc('<img src=x onerror="bad">'), '&lt;img src=x onerror=&quot;bad&quot;&gt;'));
test('Riyadh crosses date boundary at UTC 21:00',()=>assert.equal(dayKey('2026-10-14T21:30:00Z'),'2026-10-15'));
test('date input round trip preserves Riyadh time',()=>assert.equal(toInput(toISO('2026-10-15T09:30')),'2026-10-15T09:30'));
test('weekly recurrence respects end and weekday',()=>{const x={starts_at:'2026-10-15T06:00:00Z',recurrence:'weekly',recurrence_until:'2026-10-30T00:00:00Z'};assert.ok(occurs(x,'2026-10-22'));assert.ok(!occurs(x,'2026-10-23'));assert.ok(!occurs(x,'2026-11-05'));});
test('recurring event conflict detects next week',()=>{const x={id:'a',starts_at:'2026-10-15T06:00:00Z',ends_at:'2026-10-15T07:00:00Z',recurrence:'weekly'};assert.equal(conflicts({id:'b',starts_at:'2026-10-22T06:30:00Z',ends_at:'2026-10-22T07:30:00Z'},[x]).length,1);assert.equal(conflicts({id:'b',starts_at:'2026-10-22T07:00:00Z',ends_at:'2026-10-22T08:00:00Z'},[x]).length,0);});
test('progress counts unique linked children',()=>assert.equal(progress([{id:'a',parent_id:'p',kind:'task',status:'done'},{id:'b',kind:'task',status:'active'}],[{source_id:'a',target_id:'p'},{source_id:'p',target_id:'b'}],'p'),50));
