import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule, ActivatedRoute } from '@angular/router';
import { EvidenceService } from '../../services/evidence.service';
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

  constructor(
    private route: ActivatedRoute,
    private evidenceService: EvidenceService
  ) {}

  ngOnInit(): void {
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
    this.evidenceService.downloadEvidence(fileId);
  }
}
