// Event Hubs consumer: reads what SQL Server CES publishes, checkpoints to Blob Storage.
// Uses Microsoft Entra ID (managed identity in App Service, `az login` locally) - no keys.
import { EventHubConsumerClient, earliestEventPosition, latestEventPosition } from '@azure/event-hubs';
import { BlobCheckpointStore } from '@azure/eventhubs-checkpointstore-blob';
import { ContainerClient } from '@azure/storage-blob';
import { toEnvelope, isCesEnvelope, decodeChange, SegmentAssembler } from './cloudevent.js';

export class CesConsumer {
  constructor({ config, credential, store, logger = console }) {
    this.config = config; this.credential = credential; this.store = store; this.logger = logger;
    this.assembler = new SegmentAssembler();
    this.status = { state: 'stopped', partitions: {}, since: null, lastError: null };
  }

  async start() {
    const { eventHubFqdn, eventHubName, consumerGroup, checkpointBlobEndpoint, checkpointContainer, startPosition } = this.config;
    let checkpointStore;
    if (checkpointBlobEndpoint) {
      const containerUrl = `${checkpointBlobEndpoint.replace(/\/$/, '')}/${checkpointContainer}`;
      const container = new ContainerClient(containerUrl, this.credential);
      checkpointStore = new BlobCheckpointStore(container);
    }
    this.client = checkpointStore
      ? new EventHubConsumerClient(consumerGroup, eventHubFqdn, eventHubName, this.credential, checkpointStore)
      : new EventHubConsumerClient(consumerGroup, eventHubFqdn, eventHubName, this.credential);

    this.status = { state: 'starting', partitions: {}, since: new Date().toISOString(), lastError: null, checkpointing: !!checkpointStore };
    const position = startPosition === 'earliest' ? earliestEventPosition : latestEventPosition;

    this.subscription = this.client.subscribe(
      {
        processInitialize: async ctx => {
          this.status.state = 'running';
          this.status.partitions[ctx.partitionId] = { claimedAt: new Date().toISOString() };
          this.logger.info?.(`[consumer] claimed partition ${ctx.partitionId}`);
        },
        processClose: async (reason, ctx) => {
          delete this.status.partitions[ctx.partitionId];
          this.logger.info?.(`[consumer] released partition ${ctx.partitionId}: ${reason}`);
        },
        processEvents: async (events, ctx) => {
          if (!events.length) return;
          for (const ev of events) this.handle(ev, ctx.partitionId);
          if (checkpointStore) {
            try { await ctx.updateCheckpoint(events[events.length - 1]); }
            catch (e) { this.store.recordConsumerError(`Checkpoint failed: ${e.message}`); }
          }
        },
        processError: async (err, ctx) => {
          this.status.lastError = { at: new Date().toISOString(), message: err.message, partitionId: ctx?.partitionId };
          this.store.recordConsumerError(`Event Hubs (${ctx?.partitionId ?? 'n/a'}): ${err.message}`);
          this.logger.error?.('[consumer] error', err);
        },
      },
      { startPosition: position, maxBatchSize: 200, maxWaitTimeInSeconds: 1 },
    );
    this.logger.info?.(`[consumer] subscribed to ${eventHubFqdn}/${eventHubName} (${consumerGroup}), start=${startPosition}`);
  }

  handle(ev, partitionId) {
    let env;
    try {
      env = toEnvelope(ev.body, ev.properties);
      if (!isCesEnvelope(env)) { this.store.nonCes++; return; }
      const complete = this.assembler.push(env);
      if (!complete) return; // waiting for more segments
      const change = decodeChange(complete);
      this.store.addChange(change, {
        partitionId,
        offset: ev.offset,
        sequenceNumber: ev.sequenceNumber,
        enqueuedTime: ev.enqueuedTimeUtc,
        synthetic: ev.properties?.synthetic === 'true',
      });
    } catch (e) {
      let sample;
      try { sample = Buffer.isBuffer(ev.body) ? ev.body.toString('utf8') : JSON.stringify(ev.body); } catch { sample = String(ev.body); }
      this.store.recordParseError(e, sample);
    }
  }

  info() {
    return { ...this.status, pendingSegments: this.assembler.pendingCount, expiredSegments: this.assembler.expired, nonCesMessages: this.store.nonCes };
  }

  async stop() {
    await this.subscription?.close();
    await this.client?.close();
    this.status.state = 'stopped';
  }
}
