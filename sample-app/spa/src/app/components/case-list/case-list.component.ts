import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterModule } from '@angular/router';
import { EvidenceService } from '../../services/evidence.service';
import { Case } from '../../models/case.model';

@Component({
  selector: 'app-case-list',
  standalone: true,
  imports: [CommonModule, RouterModule],
  templateUrl: './case-list.component.html',
})
export class CaseListComponent implements OnInit {
  cases: Case[] = [];
  loading = true;
  error: string | null = null;

  constructor(private evidenceService: EvidenceService) {}

  ngOnInit(): void {
    this.evidenceService.getCases().subscribe({
      next: (data) => {
        this.cases = data;
        this.loading = false;
      },
      error: (err) => {
        this.error = 'Failed to load cases.';
        this.loading = false;
        console.error('Error loading cases', err);
      },
    });
  }
}
