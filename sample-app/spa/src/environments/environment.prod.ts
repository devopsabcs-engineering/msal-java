export const environment = {
  production: true,
  msalConfig: {
    clientId: '3fd702c1-b1c1-427f-a24e-700f841813d3',
    tenantId: 'aa93b9d9-037d-4f08-a26d-783cff0e2369',
    redirectUri: 'https://app-evidence-spa-workshop.azurewebsites.net',
  },
  apiConfig: {
    baseUrl: 'https://app-evidence-api-workshop.azurewebsites.net/api',
    scopes: ['api://3186f769-2e40-47e2-905b-5b9e784d0ae2/Evidence.Read'],
  },
  appInsights: {
    connectionString: 'InstrumentationKey=970e6698-ee80-475a-b83c-1e1fc5188612;IngestionEndpoint=https://canadacentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://canadacentral.livediagnostics.monitor.azure.com/;ApplicationId=6489213d-324d-429c-b1a8-db358f414b85',
  },
};
