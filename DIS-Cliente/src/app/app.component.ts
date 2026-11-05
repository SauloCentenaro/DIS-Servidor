import { HttpClient } from '@angular/common/http';
import { Component } from '@angular/core';
import { AppServiceModule } from './app.service';
import { RequestsModel } from './request.model';
import { ReturnModel } from './return.model';

import { firstValueFrom } from 'rxjs';

enum File {
  'MODEL1.csv',
  'MODEL2.csv',
  'MODEL3.csv',
}


const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
@Component({
  selector: 'app-root',
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss']
})
export class AppComponent {
  public requisicoes = 1;
  public sending = false;
  public errors: string[] = [];
  titulo = 'Desenvolvimento Integrado de Sistemas';

  allRequests: RequestsModel[] = [];
  allReturns: ReturnModel[] = [];

  PATH_MODEL1 = './assets/model1/'
  PATH_MODEL2 = './assets/model2/'

  isOpen: boolean[] = [];

  toggleAccordion(index: number) {
    this.isOpen[index] = !this.isOpen[index];
  }

  constructor(private http: HttpClient, private service: AppServiceModule) {}

  public randomizeValues(req: RequestsModel){
    req.user = Math.floor(Math.random() * 30000)
    // req.ganho = Math.random() > 0.5 ? true : false; //Desabilitado opção de enviar com ganho pois está dando errado :(
    req.ganho = false; //Caso vá reabilitar o ganho, remova/comente essa linha e libere a de cima
    req.model = Math.random() > 0.5 ? true : false;
  }

  public async loadVector(req: RequestsModel) {
    const vectorToRead = this.getRandomFilePath(req);
    const vectorLoaded = await this.readCSVFile(vectorToRead);

    req.vector = vectorLoaded;
  }

  private getRandomFilePath(req: RequestsModel): string {
    const vector = Math.floor(Math.random() * 2.999999999);
    const fileName = File[vector];
    return (req.model ? this.PATH_MODEL1 : this.PATH_MODEL2) + fileName;
  }

  private async readCSVFile(filePath: string): Promise<string[]> {
    const content = await firstValueFrom(this.http.get(filePath, { responseType: 'text' }));
    const lines = content.split(/\r?\n/).map(line => line.trim()).filter(Boolean);
    if (!lines.length || lines.some(line => !Number.isFinite(Number(line)))) {
      throw new Error('O arquivo CSV está vazio ou contém valores inválidos.');
    }
    return lines;
  }

  public async sendRequests() {
    if (this.sending) return;
    this.errors = [];
    if (!Number.isSafeInteger(this.requisicoes) || this.requisicoes < 1 || this.requisicoes > 100) {
      this.errors.push('Informe um número inteiro de requisições entre 1 e 100.');
      return;
    }
    this.sending = true;
    this.allReturns = [];
    this.allRequests = [];
    const count = this.requisicoes;
    try {
      const pending: Promise<void>[] = [];
      for (let i = 0; i < count; i++) {
        const req = new RequestsModel();
        this.randomizeValues(req);
        try {
          await this.loadVector(req);
          this.allRequests.push(req);
          pending.push(this.requestService(req));
        } catch (error: any) {
          this.errors.push(`Requisição ${i + 1}: ${error?.message || 'Não foi possível carregar o CSV.'}`);
        }
      }
      await Promise.all(pending);
    } finally {
      this.sending = false;
    }
  }

  public async requestService(req: RequestsModel): Promise<void> {
    try {
      await sleep(Math.floor(Math.random() * 5000));
      const res = await firstValueFrom(this.service.request(req));
      res.image = this.generateImage(res.imageVector);
      this.allReturns.push(res);
    } catch (error: any) {
      this.errors.push(`Usuário ${req.user}: ${error?.error?.error || error?.message || 'Falha na comunicação com o servidor.'}`);
    }
  }
  atualizarAccordion(i: number){
    let element = document.getElementById(`accordion_${i}`)
    element?.classList.contains("show") ? element?.classList.remove("show") : element?.classList.add("show")
  }

  private generateImage(vetor: number[]): string {
    const pixelSize = 10; // Define o tamanho do pixel (multiplier)
    const canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d');

    const size = Math.sqrt(vetor.length);
    if (!vetor.length || !Number.isInteger(size) || vetor.some(v => !Number.isFinite(v) || v < 0 || v > 255)) {
      throw new Error('O servidor retornou uma imagem inválida.');
    }
    const scaledSize = size * pixelSize; // Tamanho escalado

    canvas.width = scaledSize;
    canvas.height = scaledSize;

    for (let i = 0; i < vetor.length; i++) {
      const x = (i % size) * pixelSize;
      const y = Math.floor(i / size) * pixelSize;
      const grayscaleValue = vetor[i];
      if (ctx) {
        ctx.fillStyle = `rgb(${grayscaleValue}, ${grayscaleValue}, ${grayscaleValue})`;
        ctx.fillRect(x, y, pixelSize, pixelSize); // Aumenta o tamanho do pixel
      }
    }

    // Converte o canvas para imagem base64 e retorna
    return canvas.toDataURL('image/png');
  }
}
