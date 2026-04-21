import { Routes } from '@angular/router';
import { MsalGuard } from '@azure/msal-angular';
import { HomeComponent } from './components/home/home.component';
import { CaseListComponent } from './components/case-list/case-list.component';
import { CaseDetailComponent } from './components/case-detail/case-detail.component';
import { UnauthorizedComponent } from './components/unauthorized/unauthorized.component';

export const routes: Routes = [
  { path: '', component: HomeComponent },
  { path: 'cases', component: CaseListComponent, canActivate: [MsalGuard] },
  {
    path: 'cases/:id',
    component: CaseDetailComponent,
    canActivate: [MsalGuard],
  },
  { path: 'unauthorized', component: UnauthorizedComponent },
  { path: '**', redirectTo: '' },
];
