import { Injectable } from '@angular/core';
import { MsalService } from '@azure/msal-angular';
import {
  AccountInfo,
  AuthenticationResult,
  SilentRequest,
} from '@azure/msal-browser';
import { from, Observable, of } from 'rxjs';
import { catchError, map } from 'rxjs/operators';
import { loginRequest } from '../auth-config';

/**
 * Application roles defined in the Microsoft Entra ID app registration
 * (App roles → "value" field). Surfaced to the SPA via the `roles`
 * claim on the ID token.
 */
export const ROLE_CASE_READER = 'CaseReader';
export const ROLE_CASE_ADMIN = 'CaseAdmin';

/**
 * Lightweight wrapper around MsalService that exposes the role and
 * token helpers the UI needs without forcing components to know about
 * MSAL internals.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  constructor(private msalService: MsalService) {}

  /** Currently signed-in account, or null when no one is signed in. */
  getActiveAccount(): AccountInfo | null {
    const active = this.msalService.instance.getActiveAccount();
    if (active) {
      return active;
    }
    const accounts = this.msalService.instance.getAllAccounts();
    return accounts.length > 0 ? accounts[0] : null;
  }

  /** App roles from the ID token `roles` claim. */
  getRoles(): string[] {
    const account = this.getActiveAccount();
    if (!account) {
      return [];
    }
    const claims = account.idTokenClaims as
      | Record<string, unknown>
      | undefined;
    const roles = claims?.['roles'];
    return Array.isArray(roles) ? roles.map((r) => String(r)) : [];
  }

  hasAnyRole(...roles: string[]): boolean {
    if (roles.length === 0) {
      return false;
    }
    const userRoles = this.getRoles();
    return roles.some((r) => userRoles.includes(r));
  }

  /** True when the signed-in user can download evidence files. */
  canDownloadEvidence(): boolean {
    return this.hasAnyRole(ROLE_CASE_READER, ROLE_CASE_ADMIN);
  }

  /**
   * Acquire the current API access token silently from the MSAL cache,
   * refreshing via the hidden iframe / refresh token when needed.
   */
  getAccessToken(): Observable<string | null> {
    const account = this.getActiveAccount();
    if (!account) {
      return of(null);
    }
    const request: SilentRequest = {
      scopes: loginRequest.scopes,
      account,
    };
    return from(this.msalService.instance.acquireTokenSilent(request)).pipe(
      map((res: AuthenticationResult) => res.accessToken),
      catchError((err) => {
        console.warn('acquireTokenSilent failed', err);
        return of(null);
      }),
    );
  }

  /** ID token cached after the most recent sign-in. */
  getIdToken(): string | null {
    return this.getActiveAccount()?.idToken ?? null;
  }

  /**
   * Copy the supplied text to the clipboard. Returns true on success.
   * Falls back to a hidden textarea when the async clipboard API is
   * unavailable (e.g. older browsers / non-secure contexts).
   */
  async copyToClipboard(text: string): Promise<boolean> {
    if (!text) {
      return false;
    }
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch (err) {
      console.warn('navigator.clipboard.writeText failed', err);
    }
    try {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.setAttribute('readonly', '');
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      const ok = document.execCommand('copy');
      document.body.removeChild(textarea);
      return ok;
    } catch (err) {
      console.warn('Fallback clipboard copy failed', err);
      return false;
    }
  }
}
