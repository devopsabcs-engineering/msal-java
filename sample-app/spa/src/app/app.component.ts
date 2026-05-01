import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { Subject } from 'rxjs';
import { filter, takeUntil } from 'rxjs/operators';
import {
  MsalBroadcastService,
  MsalService,
} from '@azure/msal-angular';
import {
  EventMessage,
  EventType,
  InteractionStatus,
} from '@azure/msal-browser';
import { loginRequest } from './auth-config';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './app.component.html',
})
export class AppComponent implements OnInit, OnDestroy {
  isLoggedIn = false;
  username = '';
  userInitials = '';
  readonly currentYear = new Date().getFullYear();
  private readonly _destroying$ = new Subject<void>();

  constructor(
    private msalService: MsalService,
    private msalBroadcastService: MsalBroadcastService
  ) {}

  ngOnInit(): void {
    this.msalService.handleRedirectObservable().subscribe();

    this.msalBroadcastService.inProgress$
      .pipe(
        filter(
          (status: InteractionStatus) =>
            status === InteractionStatus.None
        ),
        takeUntil(this._destroying$)
      )
      .subscribe(() => {
        this.setLoginDisplay();
      });

    this.msalBroadcastService.msalSubject$
      .pipe(
        filter(
          (msg: EventMessage) =>
            msg.eventType === EventType.LOGIN_SUCCESS
        ),
        takeUntil(this._destroying$)
      )
      .subscribe(() => {
        this.setLoginDisplay();
      });
  }

  login(): void {
    this.msalService.loginRedirect(loginRequest);
  }

  logout(): void {
    this.msalService.logoutRedirect();
  }

  private setLoginDisplay(): void {
    const accounts = this.msalService.instance.getAllAccounts();
    this.isLoggedIn = accounts.length > 0;
    if (this.isLoggedIn) {
      const acct = accounts[0];
      this.username = acct.name?.trim() || acct.username || '';
      this.userInitials = this.computeInitials(this.username || acct.username || '');
    } else {
      this.username = '';
      this.userInitials = '';
    }
  }

  private computeInitials(value: string): string {
    if (!value) {
      return '';
    }
    const trimmed = value.trim();
    if (trimmed.includes('@')) {
      return trimmed.substring(0, 1).toUpperCase();
    }
    const parts = trimmed.split(/\s+/).filter(Boolean);
    if (parts.length === 1) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  }

  ngOnDestroy(): void {
    this._destroying$.next();
    this._destroying$.complete();
  }
}
