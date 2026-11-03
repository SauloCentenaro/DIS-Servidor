# Documentação técnica — servidor de reconstrução de imagens em C++

## 1. Objetivo do trabalho

Este repositório contém a implementação em C++ de um servidor para reconstrução de imagens a partir de um vetor de medições. O projeto foi preparado para ser comparado, por meio de benchmarking, com uma implementação equivalente em Elixir mantida em outra branch.

O objetivo do estudo é observar como as duas linguagens e seus respectivos modelos de execução se comportam diante da mesma carga de trabalho. A comparação deve considerar, ao menos:

- tempo de resposta e vazão do servidor;
- consumo de CPU e memória;
- comportamento sob múltiplas requisições simultâneas;
- número de iterações e resultado numérico do algoritmo;
- equivalência das imagens reconstruídas.

Para que os resultados sejam comparáveis, as duas versões devem usar as mesmas matrizes de referência, vetores de entrada, regras de ganho, tolerância, limite de iterações, hardware e perfil de carga.

## 2. Visão geral da solução

O programa expõe um servidor HTTP na porta `8080`. Cada requisição contém um documento JSON com um vetor de medições e os parâmetros da reconstrução. O servidor executa o seguinte fluxo:

1. aceita uma conexão TCP;
2. lê uma requisição HTTP de forma assíncrona;
3. interpreta o corpo como JSON;
4. converte o vetor recebido de texto para `double`;
5. escolhe e carrega uma matriz de referência em CSV;
6. opcionalmente aplica um ganho aos valores de entrada;
7. resolve o sistema pelo método CGNR;
8. converte o vetor resultante em pixels;
9. grava uma imagem PNG no disco;
10. devolve o vetor da imagem, o identificador do usuário, o número de iterações e os instantes medidos.

Fluxo resumido:

```text
Cliente HTTP
    |
    v
Server (aceita conexões)
    |
    v
Session (lê e interpreta o JSON)
    |
    +--> ModlMat (carrega H-1.csv ou H-2.csv)
    |
    +--> aplicação opcional de ganho
    |
    +--> ConjugateGradienteNR::solve()
    |
    +--> ImageGeneration (pixels + arquivo PNG)
    |
    v
Resposta JSON
```

## 3. Componentes do código

### `main.cpp`

É o ponto de entrada. Cria um `boost::asio::io_context`, instancia o servidor na porta `8080` e inicia o loop de eventos com `io_context.run()`.

### `server.hpp` e `server.cpp`

A classe `Server` mantém o `acceptor` TCP e aceita conexões de forma assíncrona. Para cada conexão aceita, cria uma instância compartilhada de `Session`. Em seguida, agenda imediatamente a aceitação da próxima conexão.

### `session.hpp` e `session.cpp`

A classe `Session` concentra o protocolo da aplicação:

- lê a requisição com Boost.Beast;
- mantém uma fila interna de requisições;
- interpreta o JSON;
- seleciona a matriz e aplica o ganho;
- chama o solver CGNR;
- gera a imagem e monta a resposta HTTP.

A sessão usa `std::enable_shared_from_this` para permanecer viva durante as operações assíncronas. A resposta permite CORS para qualquer origem, usa status HTTP `200 OK` e encerra o envio depois de processada.

### `matrix.hpp` e `matrix.cpp`

A classe `ModlMat` carrega uma matriz de números reais a partir de um CSV separado por vírgulas. O conteúdo é convertido para `Eigen::MatrixXd`. O carregador também verifica se todas as linhas possuem o mesmo número de colunas.

No fluxo atual, os arquivos esperados são:

- `utils\MatrizesRef\H-1.csv`, quando `model` é verdadeiro;
- `utils\MatrizesRef\H-2.csv`, quando `model` é falso.

Esses arquivos e diretórios não estão presentes nesta branch no estado atualmente documentado.

### `CGNR.hpp` e `CGNR.cpp`

Implementam o método **Conjugate Gradient for Normal Residual (CGNR)**. O algoritmo procura uma aproximação para o vetor de imagem `f` no sistema:

```text
H f = g
```

onde:

- `H` é a matriz de referência;
- `g` é o vetor de medições recebido;
- `f` é o vetor da imagem reconstruída.

O vetor inicial é nulo. Em cada iteração, o solver atualiza o resíduo, a direção de busca e a aproximação de `f`. A execução termina ao atingir a tolerância `1e-4` ou o limite de 20 iterações. O método devolve a melhor aproximação observada e o total de iterações executadas.

Esta é a implementação efetivamente usada pelo servidor.

### `CGNE.hpp` e `CGNE.cpp`

Contêm uma implementação alternativa baseada em gradientes conjugados, com limite de 100 iterações e a mesma tolerância. A classe está compilacionalmente disponível, mas não é chamada pelo fluxo atual do servidor.

### `ImageGeneration.hpp`

Fornece duas funções:

- `makeImage`: transforma o vetor reconstruído em uma imagem monocromática e grava `imagens\<user>.png`;
- `ImgVector`: transforma o mesmo resultado em um vetor de inteiros sem sinal para a resposta JSON.

Se o vetor tiver `3.600` posições, a imagem será de `60 × 60` pixels. Para qualquer outro tamanho, o código assume `30 × 30` e acessa as primeiras `900` posições. Cada pixel é obtido por `abs(valor) * 255` e convertido para 8 bits na imagem gravada.

### `Monitor.hpp` e `Monitor.cpp`

Esboçam a leitura de CPU e memória no Windows por meio de PDH e `GlobalMemoryStatusEx`. Esse monitor não é iniciado pelo programa atual e a coleta de CPU está incompleta, pois o contador correspondente não é adicionado à consulta.

### `util.hpp`

Centraliza inclusões e definições compartilhadas, incluindo Boost, Eigen, APIs do Windows, a biblioteca JSON e a tolerância numérica. O arquivo também contém dois caminhos absolutos antigos para matrizes, mas o fluxo atual usa os caminhos relativos definidos em `session.cpp`.

### `json.hpp`

É uma cópia incorporada da biblioteca *JSON for Modern C++* (`nlohmann::json`), usada para interpretar a entrada e serializar a resposta.

## 4. Contrato HTTP

O código não restringe o método nem o caminho da requisição. Na prática, espera-se uma requisição HTTP cujo corpo seja um JSON no formato abaixo:

```json
{
  "vector": ["0.12", "0.34", "0.56"],
  "model": false,
  "ganho": false,
  "user": 1
}
```

Campos:

| Campo | Tipo esperado | Função |
|---|---|---|
| `vector` | lista de strings numéricas | vetor de medições `g` |
| `model` | booleano | `false` seleciona `H-2.csv`; `true` seleciona `H-1.csv` |
| `ganho` | booleano | habilita a correção de ganho antes da reconstrução |
| `user` | inteiro | identifica a resposta e define o nome do PNG |

Quando `ganho` é verdadeiro, o código percorre 64 níveis e usa `436` conjuntos no modelo `false` ou `794` no modelo `true`. O fator calculado para cada nível `l` é:

```text
gamma(l) = 100 + (1 / 20) * l * sqrt(l)
```

Resposta produzida:

```json
{
  "imageVector": [12, 34, 56],
  "user": 1,
  "iteracoes": 20,
  "startTime": 10,
  "endTime": 12
}
```

| Campo | Significado |
|---|---|
| `imageVector` | pixels derivados da reconstrução |
| `user` | identificador recebido na requisição |
| `iteracoes` | iterações executadas pelo CGNR |
| `startTime` / `endTime` | valores baseados em `clock()` e truncados para segundos |

## 5. Concorrência e ciclo de vida

O servidor usa I/O assíncrono e pode manter várias sessões em andamento no mesmo `io_context`. Entretanto, `main.cpp` executa apenas uma chamada a `io_context.run()` e não cria um conjunto de threads. Portanto, as operações de leitura e escrita são assíncronas, mas o trabalho de CPU da reconstrução é executado no único thread do loop de eventos.

Isso é importante para o benchmark: uma reconstrução longa bloqueia temporariamente o atendimento das demais sessões. A comparação com Elixir deve explicitar se pretende medir exatamente esse desenho ou comparar implementações com paralelismo equivalente.

Embora exista uma fila em cada `Session`, a implementação lê somente uma requisição por conexão, define `keep_alive(false)` e encerra o lado de envio do socket após a resposta. Na prática, cada conexão atende uma requisição.

## 6. Dependências e ambiente esperado

O código foi escrito para Windows e depende de:

- compilador C++ com suporte aos recursos usados pelo projeto;
- Boost.Asio e Boost.Beast;
- Eigen;
- OpenCV;
- APIs do Windows (`winsock2`, `windows.h` e `pdh`);
- matrizes `H-1.csv` e `H-2.csv` nos caminhos esperados;
- diretório `imagens` com permissão de escrita.

Esta branch não contém `CMakeLists.txt`, `Makefile`, arquivo de projeto do Visual Studio ou instruções de compilação. Assim, não há um comando de build reproduzível apenas com os arquivos versionados. A configuração de include paths e o vínculo das bibliotecas precisam ser fornecidos pelo ambiente de desenvolvimento antes da execução.

## 7. Pontos de atenção encontrados

Os itens abaixo descrevem o comportamento atual e devem ser considerados antes de interpretar os resultados do benchmark:

1. **Matrizes ausentes:** os CSVs necessários não estão versionados nesta branch.
2. **Medição de tempo imprecisa:** `clock()` mede tempo de CPU do processo, não latência de parede. A divisão ocorre antes do armazenamento e reduz a resolução a segundos inteiros.
3. **Erros retornam sucesso HTTP:** falhas de JSON, conversão, matriz ou solver podem resultar em corpo vazio, ainda com status `200 OK`.
4. **Validação de entrada limitada:** não há validação explícita do tamanho do vetor em relação à matriz nem dos campos obrigatórios.
5. **Conversões descartadas:** valores inválidos do vetor são ignorados após uma mensagem no console, o que pode alterar silenciosamente sua dimensão.
6. **Índice do ganho:** a expressão usada é `eigenVector[l * c]`. Ela repete o índice zero quando `c = 0` e não representa o endereçamento linear usual `l + 64 * c`; deve ser confirmada com o modelo matemático antes da comparação.
7. **Dimensão da imagem:** qualquer resultado que não possua exatamente `3.600` elementos é tratado como se tivesse pelo menos `900`.
8. **Escala dos pixels:** não há normalização nem saturação explícita antes da conversão. Valores fora da faixa esperada podem produzir diferenças entre o vetor JSON e o PNG.
9. **Estado reutilizado na sessão:** a requisição removida da fila é copiada para `current_request`, mas o processamento consulta `request_`, e não essa cópia. Isso não aparece no caso atual de uma requisição por conexão, mas torna a fila inconsistente para uso futuro.
10. **Monitor não operacional:** o monitor de recursos não participa da execução e sua rotina de CPU usa um contador não inicializado.
11. **Portabilidade limitada:** caminhos com barra invertida e APIs do Windows impedem uma compilação direta em outros sistemas.

## 8. Protocolo recomendado para o benchmark

Para produzir resultados reproduzíveis e úteis, recomenda-se:

1. definir casos de teste fixos para os dois modelos e para ganho ligado/desligado;
2. validar previamente que C++ e Elixir produzem vetores, imagens e números de iterações equivalentes, com uma tolerância numérica declarada;
3. fazer um período de aquecimento antes de coletar medidas;
4. medir latência de parede no cliente, incluindo percentis como p50, p95 e p99;
5. medir vazão em requisições por segundo;
6. coletar CPU, memória residente e falhas durante a carga com uma ferramenta externa igual para ambas as versões;
7. testar níveis crescentes de concorrência;
8. executar várias repetições e registrar mediana, dispersão e intervalos de confiança;
9. manter fixos máquina, sistema operacional, matrizes, entrada, versão do compilador/runtime e configuração de paralelismo;
10. separar, quando necessário, o custo de carregamento dos CSVs, cálculo numérico, gravação do PNG e transporte HTTP.

Uma comparação inicial pode usar a seguinte matriz de cenários:

| Cenário | Modelo | Ganho | Concorrência |
|---|---:|---:|---:|
| A | H-2 | não | 1 |
| B | H-2 | sim | 1 |
| C | H-1 | não | 1 |
| D | H-1 | sim | 1 |
| E–H | mesmos casos | ambos | 10, 50 e 100 |

Os campos `startTime` e `endTime` atuais não devem ser usados isoladamente para comparar latência. O ideal é medir o tempo externamente e, se forem necessárias métricas internas, substituir essa medição por um relógio monotônico de alta resolução nas duas implementações.

## 9. Escopo atual da branch

Esta documentação descreve o código disponível na branch `main` no commit `695572f` (`Mais algumas mudanças`). Ela registra o comportamento observado no código-fonte, inclusive componentes incompletos e limitações, sem presumir funcionalidades que não estejam implementadas.
