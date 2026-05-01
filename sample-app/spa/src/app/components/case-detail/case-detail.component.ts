import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, ActivatedRoute } from '@angular/router';
import { EvidenceService } from '../../services/evidence.service';
import {
  AuthService,
  ROLE_CASE_ADMIN,
  ROLE_CASE_READER,
} from '../../services/auth.service';
import { Case } from '../../models/case.model';

@Component({
  selector: 'app-case-detail',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './case-detail.component.html',
})
export class CaseDetailComponent implements OnInit {
  caseData: Case | null = null;
  loading = true;
  error: string | null = null;
  canDownload = false;
  roles: string[] = [];

  readonly downloadDisabledReason = `You need the ${ROLE_CASE_READER} or ${ROLE_CASE_ADMIN} app role to download evidence.`;

  constructor(
    private route: ActivatedRoute,
    private evidenceService: EvidenceService,
    private authService: AuthService,
  ) {}

  ngOnInit(): void {
    this.roles = this.authService.getRoles();
    this.canDownload = this.authService.canDownloadEvidence();

    const id = this.route.snapshot.paramMap.get('id');
    if (id) {
      this.evidenceService.getCaseById(id).subscribe({
        next: (data) => {
          this.caseData = data;
          this.loading = false;
        },
        error: (err) => {
          this.error = 'Failed to load case details.';
          this.loading = false;
          console.error('Error loading case', err);
        },
      });
    }
  }

  download(fileId: string): void {
    if (!this.canDownload) {
      return;
    }
    this.evidenceService.downloadEvidence(fileId);
  }
}
