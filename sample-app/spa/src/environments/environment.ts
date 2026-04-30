export const environment = {
  production: false,
  msalConfig: {
    clientId: '3fd702c1-b1c1-427f-a24e-700f841813d3',
    tenantId: 'aa93b9d9-037d-4f08-a26d-783cff0e2369',
    redirectUri: 'http://localhost:4200',
  },
  apiConfig: {
    baseUrl: '/api',
    scopes: ['api://3186f769-2e40-47e2-905b-5b9e784d0ae2/Evidence.Read'],
  },
  appInsights: {
    connectionString: '',
  },
};
