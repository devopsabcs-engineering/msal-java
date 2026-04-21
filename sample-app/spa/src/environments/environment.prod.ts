export const environment = {
  production: true,
  msalConfig: {
    clientId: 'YOUR_SPA_CLIENT_ID',
    tenantId: 'YOUR_TENANT_ID',
    redirectUri: 'https://YOUR_SPA_APP_NAME.azurewebsites.net',
  },
  apiConfig: {
    baseUrl: 'https://YOUR_API_APP_NAME.azurewebsites.net/api',
    scopes: ['api://YOUR_API_CLIENT_ID/Evidence.Read'],
  },
  appInsights: {
    connectionString: 'YOUR_CONNECTION_STRING',
  },
};
