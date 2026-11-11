import { TestBed } from '@angular/core/testing';
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';
import { AppServiceModule } from './app.service';
import { RequestsModel } from './request.model';
import { ReturnModel } from './return.model';

describe('AppServiceModule dual-backend contract', () => {
  let service: AppServiceModule;
  let http: HttpTestingController;

  beforeEach(() => {
    TestBed.configureTestingModule({imports: [HttpClientTestingModule]});
    service = TestBed.inject(AppServiceModule);
    http = TestBed.inject(HttpTestingController);
  });

  afterEach(() => http.verify());

  it('sends every reconstruction to both backends', () => {
    const request = {model: false, ganho: false, user: 7, vector: ['1']} as RequestsModel;
    const response = {user: 7, iteracoes: 1, imageVector: [0], startTime: 1, endTime: 2, durationSeconds: 1} as ReturnModel;
    let actual: ReturnModel | undefined;
    service.request(request).subscribe(value => actual = value);
    http.expectOne('/api/cpp/reconstruct').flush(response);
    http.expectOne('/api/elixir/reconstruct').flush({...response});
    expect(actual).toEqual(response);
  });

  it('rejects a logical divergence', () => {
    const request = {model: false, ganho: false, user: 7, vector: ['1']} as RequestsModel;
    const response = {user: 7, iteracoes: 1, imageVector: [0], startTime: 1, endTime: 2, durationSeconds: 1} as ReturnModel;
    let message = '';
    service.request(request).subscribe({error: error => message = error.message});
    http.expectOne('/api/cpp/reconstruct').flush(response);
    http.expectOne('/api/elixir/reconstruct').flush({...response, imageVector: [255]});
    expect(message).toContain('Divergência lógica');
  });
});
