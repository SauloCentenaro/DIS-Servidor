import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { forkJoin, map, Observable } from 'rxjs';
import { RequestsModel } from './request.model';
import { ReturnModel } from './return.model';

@Injectable({
  providedIn: 'root',
})
export class AppServiceModule {
  private cppUrl = '/api/cpp';
  private elixirUrl = '/api/elixir';

  constructor(private http: HttpClient) {}

  teste(): Observable<any> {
    return forkJoin({
      cpp: this.http.get<{status: string}>(`${this.cppUrl}/health`),
      elixir: this.http.get<{status: string}>(`${this.elixirUrl}/health`),
    }).pipe(map(({cpp, elixir}) => {
      if (cpp.status !== 'ok' || elixir.status !== 'ok') throw new Error('Um dos backends não está saudável.');
      return {status: 'ok', backends: ['cpp', 'elixir']};
    }));
  }

  request(i: RequestsModel): Observable<ReturnModel> {
    return forkJoin({
      cpp: this.http.post<ReturnModel>(`${this.cppUrl}/reconstruct`, i),
      elixir: this.http.post<ReturnModel>(`${this.elixirUrl}/reconstruct`, i),
    }).pipe(map(({cpp, elixir}) => {
      this.assertEquivalent(cpp, elixir);
      return cpp;
    }));
  }

  private assertEquivalent(cpp: ReturnModel, elixir: ReturnModel): void {
    const samePixels = cpp.imageVector.length === elixir.imageVector.length &&
      cpp.imageVector.every((value, index) => value === elixir.imageVector[index]);
    if (cpp.user !== elixir.user || cpp.iteracoes !== elixir.iteracoes || !samePixels) {
      throw new Error('Divergência lógica entre os backends C++ e Elixir.');
    }
  }
}
