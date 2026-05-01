import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { MsalService } from '@azure/msal-angular';
import { loginRequest } from '../../auth-config';
import { EvidenceService } from '../../services/evidence.service';
import { UserClaims } from '../../models/case.model';
import { TokenInspectorComponent } from '../token-inspector/token-inspector.component';

@Component({
  selector: 'app-home',
  standalone: true,
  imports: [CommonModule, RouterModule, TokenInspectorComponent],
  templateUrl: './home.component.html',
})
export class HomeComponent implements OnInit {
  isLoggedIn = false;
  user: UserClaims | null = null;

  constructor(
    private msalService: MsalService,
    private evidenceService: EvidenceService
  ) {}

  ngOnInit(): void {
    this.isLoggedIn =
      this.msalService.instance.getAllAccounts().length > 0;
    if (this.isLoggedIn) {
      this.evidenceService.getMe().subscribe({
        next: (claims) => (this.user = claims),
        error: () => (this.user = null),
      });
    }
  }

  login(): void {
    this.msalService.loginRedirect(loginRequest);
  }
}
