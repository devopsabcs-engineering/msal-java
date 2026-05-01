import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { AuthService } from '../../services/auth.service';

type TokenKind = 'access' | 'id';

@Component({
  selector: 'app-token-inspector',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './token-inspector.component.html',
})
export class TokenInspectorComponent implements OnInit {
  /** Latest acquired access token (cached for the panel's lifetime). */
  accessToken: string | null = null;
  /** ID token from the active MSAL account. */
  idToken: string | null = null;
  /** Status message shown next to the action buttons. */
  status: string | null = null;
  /** When true, the raw token strings are revealed in the UI. */
  showAccessToken = false;
  showIdToken = false;
  loadingAccessToken = false;

  constructor(private authService: AuthService) {}

  ngOnInit(): void {
    this.idToken = this.authService.getIdToken();
    this.refreshAccessToken();
  }

  refreshAccessToken(forceRefresh = false): void {
    this.loadingAccessToken = true;
    if (forceRefresh) {
      this.status = 'Requesting a fresh access token from Entra ID…';
    }
    const previousToken = this.accessToken;
    this.authService.getAccessToken(forceRefresh).subscribe((token) => {
      this.accessToken = token;
      this.loadingAccessToken = false;
      if (!token) {
        this.status =
          'Could not silently acquire an access token. Sign out and sign back in if this persists.';
        return;
      }
      if (forceRefresh) {
        this.status =
          token === previousToken
            ? 'Entra returned the same access token (still valid in the cache).'
            : 'Access token refreshed.';
      }
    });
  }

  toggleAccessTokenVisibility(): void {
    this.showAccessToken = !this.showAccessToken;
  }

  toggleIdTokenVisibility(): void {
    this.showIdToken = !this.showIdToken;
  }

  async copyToken(kind: TokenKind): Promise<void> {
    const token = this.tokenFor(kind);
    if (!token) {
      this.status = `No ${this.label(kind)} is currently available.`;
      return;
    }
    const ok = await this.authService.copyToClipboard(token);
    this.status = ok
      ? `${this.label(kind)} copied to clipboard.`
      : `Could not copy the ${this.label(kind)} automatically — copy it manually below.`;
    if (!ok) {
      // Reveal the token so the user can copy it by hand.
      if (kind === 'access') {
        this.showAccessToken = true;
      } else {
        this.showIdToken = true;
      }
    }
  }

  /**
   * Open the token in jwt.ms using the URL fragment so the value is
   * never sent to a server. jwt.ms only inspects the fragment in-page.
   */
  openInJwtMs(kind: TokenKind): void {
    const token = this.tokenFor(kind);
    if (!token) {
      this.status = `No ${this.label(kind)} is currently available.`;
      return;
    }
    const url =
      kind === 'access'
        ? `https://jwt.ms/#access_token=${encodeURIComponent(token)}`
        : `https://jwt.ms/#id_token=${encodeURIComponent(token)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  }

  preview(token: string | null): string {
    if (!token) {
      return '—';
    }
    if (token.length <= 24) {
      return token;
    }
    return `${token.substring(0, 12)}…${token.substring(token.length - 12)}`;
  }

  private tokenFor(kind: TokenKind): string | null {
    return kind === 'access' ? this.accessToken : this.idToken;
  }

  private label(kind: TokenKind): string {
    return kind === 'access' ? 'Access token' : 'ID token';
  }
}
