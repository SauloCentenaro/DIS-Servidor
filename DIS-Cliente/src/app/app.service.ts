import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { RequestsModel } from './request.model';
import { ReturnModel } from './return.model';

@Injectable({
  providedIn: 'root',
})
export class AppServiceModule {
  private apiUrl = '/api';

  constructor(private http: HttpClient) {}

  teste(): Observable<any> {
    const url = `${this.apiUrl}/health`;
    return this.http.get(url);
  }

  request(i: RequestsModel): Observable<ReturnModel> {
    return this.http.post<ReturnModel>(this.apiUrl, i)
  }
}
