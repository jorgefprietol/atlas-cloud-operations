export interface Operation {
  id: string; title: string; kind: string; region: string; classification: string; retentionDays: number;
  status: 'queued' | 'validated' | 'rejected'; decision: string | null; reportKey: string | null; createdAt: string;
}
export interface Audit { action: string; detail: string; createdAt: string }
export const kinds: Record<string, string> = { backup: 'Respaldo de datos', 'data-export': 'Exportación de datos', 'service-release': 'Publicación de servicio' };
export const statuses = { queued: 'En evaluación', validated: 'Validada', rejected: 'Rechazada' };
export function summarize(items: Operation[]) {
  return { total: items.length, validated: items.filter(x => x.status === 'validated').length,
    queued: items.filter(x => x.status === 'queued').length, rejected: items.filter(x => x.status === 'rejected').length };
}
