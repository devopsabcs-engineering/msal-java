export const environment = {
  production: false,
  msalConfig: {
    clientId: 'YOUR_SPA_CLIENT_ID',
    tenantId: 'YOUR_TENANT_ID',
    redirectUri: 'http://localhost:4200',
  },
  apiConfig: {
    baseUrl: '/api',
    scopes: ['api://YOUR_API_CLIENT_ID/Evidence.Read'],
  },
  appInsights: {
    connectionString: '',
  },
};
