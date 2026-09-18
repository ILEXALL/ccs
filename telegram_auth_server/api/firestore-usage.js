const {debugAccessStatus} = require('../lib/debug-access');
const { monitoringConfig } = require('../lib/monitoring-config');
const { GoogleAuth } = require('google-auth-library');

const MONITORING_SCOPE = 'https://www.googleapis.com/auth/monitoring.read';
const MONITORING_BASE = 'https://monitoring.googleapis.com/v3';

function startOfTodayIso() {
  const now = new Date();
  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())).toISOString();
}

function secondsAgoIso(seconds) {
  return new Date(Date.now() - seconds * 1000).toISOString();
}

function pointValue(point) {
  const value = point?.value || {};
  if (value.int64Value !== undefined) return Number(value.int64Value) || 0;
  if (value.doubleValue !== undefined) return Number(value.doubleValue) || 0;
  return 0;
}

function sumTimeSeries(series) {
  let total = 0;
  for (const item of series || []) {
    for (const point of item.points || []) {
      total += pointValue(point);
    }
  }
  return Math.round(total);
}

function latestGaugeSum(series) {
  let total = 0;
  for (const item of series || []) {
    const point = item.points?.[0];
    if (point) total += pointValue(point);
  }
  return Math.round(total);
}

async function listTimeSeries({
  token,
  projectId,
  metricType,
  startTime,
  endTime,
  aligner,
  reducer,
  groupByFields = [],
  onSample,
}) {
  const url = new URL(`${MONITORING_BASE}/projects/${projectId}/timeSeries`);
  url.searchParams.set('filter', `metric.type="${metricType}" AND resource.type="firestore.googleapis.com/Database"`);
  url.searchParams.set('interval.startTime', startTime);
  url.searchParams.set('interval.endTime', endTime);
  url.searchParams.set('view', 'FULL');
  url.searchParams.set('aggregation.alignmentPeriod', '60s');
  url.searchParams.set('aggregation.perSeriesAligner', aligner);

  if (reducer) {
    url.searchParams.set('aggregation.crossSeriesReducer', reducer);
  }

  for (const field of groupByFields) {
    url.searchParams.append('aggregation.groupByFields', field);
  }

  const series = [];
  do {
    const response = await fetch(url, {headers: {Authorization: `Bearer ${token}`}});
    if (!response.ok) {
      if (response.status === 403) throw new Error('Monitoring permission missing: grant roles/monitoring.viewer to the configured usage-reader service account in this Firebase project.');
      throw new Error(`Google Cloud metrics unavailable (HTTP ${response.status}).`);
    }
    const body = await response.json();
    for (const item of body.timeSeries || []) {
      series.push(item);
      for (const point of item.points || []) onSample?.(point.interval?.endTime);
    }
    if (!body.nextPageToken) break;
    url.searchParams.set('pageToken', body.nextPageToken);
  } while (true);
  return series;
}

async function readDeltaMetric(args) {
  const series = await listTimeSeries({
    ...args,
    aligner: 'ALIGN_SUM',
    reducer: 'REDUCE_SUM',
  });

  return sumTimeSeries(series);
}

async function readMetricByType(args) {
  const series = await listTimeSeries({
    ...args,
    aligner: 'ALIGN_SUM',
    reducer: 'REDUCE_SUM',
    groupByFields: ['metric.labels.type'],
  });

  const result = { query: 0, lookup: 0 };

  for (const item of series) {
    const type = String(item.metric?.labels?.type || '').toUpperCase();
    const value = sumTimeSeries([item]);

    if (type === 'QUERY') {
      result.query += value;
    }

    if (type === 'LOOKUP') {
      result.lookup += value;
    }
  }

  return result;
}

async function readGaugeMetric(args) {
  const series = await listTimeSeries({
    ...args,
    aligner: 'ALIGN_MEAN',
    reducer: 'REDUCE_SUM',
  });

  return latestGaugeSum(series);
}

module.exports = async function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({
      ok: false,
      error: 'Method not allowed',
    });
  }

  try {
    const access = await debugAccessStatus(req);
    if (access !== 200) return res.status(access).json({ok: false, error: access === 401 ? 'Unauthorized' : 'Admin access required'});
    const { credentials, projectId } = monitoringConfig();

    const auth = new GoogleAuth({
      credentials,
      scopes: [MONITORING_SCOPE],
    });

    const client = await auth.getClient();
    const token = (await client.getAccessToken()).token;

    const endTime = new Date().toISOString();
    const dayStart = startOfTodayIso();
    const recentStart = secondsAgoIso(10 * 60);

    let sampledThroughMillis = 0;
    const onSample = (time) => { sampledThroughMillis = Math.max(sampledThroughMillis, Date.parse(time) || 0); };
    const common = {
      onSample,
      token,
      projectId,
      startTime: dayStart,
      endTime,
    };

    const [
      reads,
      writes,
      deletes,
      readTypes,
      activeConnections,
      snapshotListeners,
    ] = await Promise.all([
      readDeltaMetric({
        ...common,
        metricType: 'firestore.googleapis.com/document/read_ops_count',
      }),
      readDeltaMetric({
        ...common,
        metricType: 'firestore.googleapis.com/document/write_ops_count',
      }),
      readDeltaMetric({
        ...common,
        metricType: 'firestore.googleapis.com/document/delete_ops_count',
      }),
      readMetricByType({
        ...common,
        metricType: 'firestore.googleapis.com/document/read_ops_count',
      }),
      readGaugeMetric({
        token,
        projectId,
        startTime: recentStart,
        endTime,
        metricType: 'firestore.googleapis.com/network/active_connections',
      }),
      readGaugeMetric({
        token,
        projectId,
        startTime: recentStart,
        endTime,
        metricType: 'firestore.googleapis.com/network/snapshot_listeners',
      }),
    ]);

    if (!sampledThroughMillis) throw new Error('No Firestore metric samples are available for today yet.');
    return res.status(200).json({
      sampledThroughMillis,
      ok: true,
      source: 'google_cloud_monitoring',
      window: 'Today (UTC)',
      generatedAtMillis: Date.now(),
      period: {
        startMillis: new Date(dayStart).getTime(),
        endMillis: Date.now(),
      },
      totals: {
        reads,
        writes,
        deletes,
      },
      readTypes,
      network: {
        activeConnections,
        snapshotListeners,
      },
    });
  } catch (error) {
    return res.status(500).json({
      ok: false,
      error: error?.message || String(error),
    });
  }
};