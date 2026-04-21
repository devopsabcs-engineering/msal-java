import { Component, OnDestroy, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { Subject } from 'rxjs';
import { filter, takeUntil } from 'rxjs/operators';
import {
  MsalBroadcastService,
  MsalModule,
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
  imports: [CommonModule, RouterModule, MsalModule],
  templateUrl: './app.component.html',
})
export class AppComponent implements OnInit, OnDestroy {
  isLoggedIn = false;
  private readonly _destroying$ = new Subject<void>();

  constructor(
    private msalService: MsalService,
    private msalBroadcastService: MsalBroadcastService
  ) {}

  ngOnInit(): void {
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
    this.isLoggedIn =
      this.msalService.instance.getAllAccounts().length > 0;
  }

  ngOnDestroy(): void {
    this._destroying$.next();
    this._destroying$.complete();
  }
}
