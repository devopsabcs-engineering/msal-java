import {
  MsalGuardConfiguration,
  MsalInterceptorConfiguration,
} from '@azure/msal-angular';
import {
  BrowserCacheLocation,
  InteractionType,
  LogLevel,
  PublicClientApplication,
} from '@azure/msal-browser';
import { environment } from '../environments/environment';

export const msalConfig = {
  auth: {
    clientId: environment.msalConfig.clientId,
    authority: `https://login.microsoftonline.com/${environment.msalConfig.tenantId}`,
    redirectUri: environment.msalConfig.redirectUri,
  },
  cache: {
    cacheLocation: BrowserCacheLocation.SessionStorage,
  },
  system: {
    loggerOptions: {
      logLevel: LogLevel.Warning,
      piiLoggingEnabled: false,
    },
  },
};

export const protectedResourceMap = new Map<string, Array<string>>([
  [`${environment.apiConfig.baseUrl}/*`, environment.apiConfig.scopes],
]);

export const loginRequest = {
  scopes: environment.apiConfig.scopes,
};

export function MSALInstanceFactory(): PublicClientApplication {
  return new PublicClientApplication(msalConfig);
}

export function MSALGuardConfigFactory(): MsalGuardConfiguration {
  return {
    interactionType: InteractionType.Redirect,
    authRequest: loginRequest,
  };
}

export function MSALInterceptorConfigFactory(): MsalInterceptorConfiguration {
  return {
    interactionType: InteractionType.Redirect,
    protectedResourceMap,
  };
}
