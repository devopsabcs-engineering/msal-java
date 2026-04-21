import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { Case, UserClaims } from '../models/case.model';
import { environment } from '../../environments/environment';

@Injectable({
  providedIn: 'root',
})
export class EvidenceService {
  private baseUrl = environment.apiConfig.baseUrl;

  constructor(private http: HttpClient) {}

  getCases(): Observable<Case[]> {
    return this.http.get<Case[]>(`${this.baseUrl}/cases`);
  }

  getCaseById(id: string): Observable<Case> {
    return this.http.get<Case>(`${this.baseUrl}/cases/${id}`);
  }

  downloadEvidence(fileId: string): void {
    this.http
      .get(`${this.baseUrl}/evidence/${fileId}/download`, {
        responseType: 'blob',
        observe: 'response',
      })
      .subscribe((response) => {
        const contentDisposition = response.headers.get('Content-Disposition');
        let filename = `evidence-${fileId}`;
        if (contentDisposition) {
          const match = contentDisposition.match(/filename="?([^";\s]+)"?/);
          if (match) {
            filename = match[1];
          }
        }
        const blob = response.body;
        if (blob) {
          const url = window.URL.createObjectURL(blob);
          const anchor = document.createElement('a');
          anchor.href = url;
          anchor.download = filename;
          anchor.click();
          window.URL.revokeObjectURL(url);
        }
      });
  }

  getMe(): Observable<UserClaims> {
    return this.http.get<UserClaims>(`${this.baseUrl}/me`);
  }
}
