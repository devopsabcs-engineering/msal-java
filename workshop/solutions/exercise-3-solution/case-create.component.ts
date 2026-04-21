import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { ReactiveFormsModule, FormBuilder, FormGroup, Validators } from '@angular/forms';
import { Router } from '@angular/router';
import { HttpErrorResponse } from '@angular/common/http';
import { EvidenceService } from '../../services/evidence.service';

@Component({
  selector: 'app-case-create',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  template: `
    <div class="case-create-container">
      <h2>Create New Case</h2>

      <form [formGroup]="caseForm" (ngSubmit)="onSubmit()">
        <div class="form-group">
          <label for="title">Title</label>
          <input id="title" formControlName="title" type="text" />
          @if (caseForm.get('title')?.invalid && caseForm.get('title')?.touched) {
            <span class="error">Title is required.</span>
          }
        </div>

        <div class="form-group">
          <label for="description">Description</label>
          <textarea id="description" formControlName="description" rows="4"></textarea>
          @if (caseForm.get('description')?.invalid && caseForm.get('description')?.touched) {
            <span class="error">Description is required.</span>
          }
        </div>

        <div class="form-group">
          <label for="status">Status</label>
          <select id="status" formControlName="status">
            <option value="Open">Open</option>
            <option value="Under Review">Under Review</option>
            <option value="Closed">Closed</option>
          </select>
        </div>

        <div class="form-actions">
          <button type="submit" [disabled]="caseForm.invalid || submitting">
            {{ submitting ? 'Creating...' : 'Create Case' }}
          </button>
          <button type="button" (click)="onCancel()">Cancel</button>
        </div>

        @if (errorMessage) {
          <div class="error-banner">{{ errorMessage }}</div>
        }
      </form>
    </div>
  `,
  styles: [`
    .case-create-container { max-width: 600px; margin: 2rem auto; padding: 1rem; }
    .form-group { margin-bottom: 1rem; }
    .form-group label { display: block; margin-bottom: 0.25rem; font-weight: 600; }
    .form-group input, .form-group textarea, .form-group select {
      width: 100%; padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px;
    }
    .form-actions { display: flex; gap: 0.5rem; margin-top: 1rem; }
    .form-actions button { padding: 0.5rem 1rem; border-radius: 4px; cursor: pointer; }
    .form-actions button[type="submit"] {
      background-color: #0078d4; color: white; border: none;
    }
    .form-actions button[type="submit"]:disabled { opacity: 0.6; cursor: not-allowed; }
    .form-actions button[type="button"] { background-color: #f3f3f3; border: 1px solid #ccc; }
    .error { color: #d13438; font-size: 0.85rem; }
    .error-banner {
      margin-top: 1rem; padding: 0.75rem; background-color: #fde7e9;
      border: 1px solid #d13438; border-radius: 4px; color: #d13438;
    }
  `],
})
export class CaseCreateComponent {
  private fb = inject(FormBuilder);
  private router = inject(Router);
  private evidenceService = inject(EvidenceService);

  submitting = false;
  errorMessage = '';

  caseForm: FormGroup = this.fb.group({
    title: ['', Validators.required],
    description: ['', Validators.required],
    status: ['Open'],
  });

  onSubmit(): void {
    if (this.caseForm.invalid) {
      return;
    }

    this.submitting = true;
    this.errorMessage = '';

    this.evidenceService.createCase(this.caseForm.value).subscribe({
      next: () => {
        this.router.navigate(['/cases']);
      },
      error: (err: HttpErrorResponse) => {
        this.submitting = false;
        if (err.status === 403) {
          this.errorMessage =
            'You do not have the CaseAdmin role. Assign the role in Entra ID, then sign out and sign back in.';
          this.router.navigate(['/unauthorized']);
        } else {
          this.errorMessage = `Failed to create case: ${err.message}`;
        }
      },
    });
  }

  onCancel(): void {
    this.router.navigate(['/cases']);
  }
}
