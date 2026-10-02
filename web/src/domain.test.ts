import { describe, it, expect } from 'vitest';
import { summarize, type Operation } from './domain';
describe('Operational summary', () => {
  it('separates pending and final outcomes', () => {
    const items = ['validated','queued','rejected','validated'].map(status => ({ status } as Operation));
    expect(summarize(items)).toEqual({ total: 4, validated: 2, queued: 1, rejected: 1 });
  });
  it('handles an empty account', () => expect(summarize([]).total).toBe(0));
});
