import { fakeAsync, tick, flushMicrotasks } from '@angular/core/testing';
import { of, throwError } from 'rxjs';
import { AppComponent } from './app.component';
import { RequestsModel } from './request.model';

describe('AppComponent request handling', () => {
  let component: AppComponent;
  let http: any;
  let service: any;
  beforeEach(() => {
    http = { get: jasmine.createSpy().and.returnValue(of('1\n2\n')) };
    service = { request: jasmine.createSpy() };
    component = new AppComponent(http, service);
  });
  it('filters trailing blank CSV lines', async () => {
    const req = new RequestsModel();
    await component.loadVector(req);
    expect(req.vector).toEqual(['1', '2']);
  });
  it('does not send a request when the CSV fails', async () => {
    http.get.and.returnValue(throwError(() => new Error('CSV indisponível')));
    await component.sendRequests();
    expect(service.request).not.toHaveBeenCalled();
    expect(component.errors.length).toBe(1);
    expect(component.sending).toBeFalse();
  });
  it('blocks a second batch until all responses complete', async () => {
    let finish!: () => void;
    const pending = new Promise<void>(resolve => finish = resolve);
    const send = spyOn(component, 'requestService').and.returnValue(pending);
    const batch = component.sendRequests();
    await Promise.resolve();
    await Promise.resolve();
    await component.sendRequests();
    expect(component.sending).toBeTrue();
    finish();
    await batch;
    expect(send).toHaveBeenCalledTimes(1);
    expect(component.sending).toBeFalse();
  });
  it('shows API errors and completes the request', fakeAsync(() => {
    spyOn(Math, 'random').and.returnValue(0);
    service.request.and.returnValue(throwError(() => ({ error: { error: 'Vetor inválido' } })));
    const req = new RequestsModel(); req.user = 7;
    component.requestService(req);
    tick(0);
    flushMicrotasks();
    expect(component.errors[0]).toContain('Vetor inválido');
    expect(component.allReturns.length).toBe(0);
  }));
  it('rejects invalid request counts', async () => {
    component.requisicoes = 1.5;
    await component.sendRequests();
    expect(http.get).not.toHaveBeenCalled();
    expect(component.errors.length).toBe(1);
  });
});
