export interface Case {
  id: string;
  title: string;
  status: 'Open' | 'Closed' | 'Under Review';
  assignedTo: string;
  description: string;
  evidenceFiles: EvidenceFile[];
}

export interface EvidenceFile {
  id: string;
  filename: string;
  classification: 'Confidential' | 'Restricted' | 'Public';
  uploadedAt: string;
  sizeBytes: number;
}

export interface UserClaims {
  name: string;
  email: string;
  roles: string[];
}
