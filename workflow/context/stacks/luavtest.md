<!-- Context: development/testing/luavtest | Priority: high | Version: 1.0 | Updated: 2026-09-16 -->

# luavtest — Sequenciador de cenários da infra Dígitro

**Purpose**: como escrever, rodar e depurar cenários de teste com o `luavtest`, o sequenciador
proprietário da Dígitro (`bibliotecas/luavtest.git`, submódulo `luavtest/`).

**Quando ler**: qualquer projeto C ou Lua da infra Dígitro que tenha `tests/testenv.lua` e
`luavtest/` como submódulo. Hoje conhecemos o `ctrlic-md`, mas a ferramenta serve todos os
processos da infra básica (os `trata-*`) — o que está aqui é da **ferramenta**, não de um projeto.

**Quando NÃO ler**: projetos Node, Python ou React. Nada aqui se aplica.

> A documentação oficial é `luavtest/README.txt`, ~550 linhas, **em latin-1**. `grep` a trata como
> binário e devolve silêncio — use `grep -a` ou `iconv -f latin1 -t utf8`. Muita gente conclui que
> não existe documentação por causa disso.

---

## 1. O modelo

Virtualiza a infra `utilmsg`/`txtcp`: timers, conexões, recepção e envio de pacotes, traces. O
executável de teste é linkado com `luavtest/libvtest.so` **no lugar** de `utilmsg.so`, `txtcp.so`,
`libpreserv.so` e `xmlrpc_server.so`. Quando o alvo chama `loop_msg()`, o sequenciador assume.

Duas fases, nesta ordem:

- **boot** — estabelece as condições de operação (conexões, protocolos de iniciação). Um único
  perfil de boot por bateria.
- **operação** — aplica os cenários da lista, um a um.

Cenário é máquina de estados: forja eventos de entrada no alvo e valida a sequência de pacotes de
saída, incluindo o **destino** (peer) de cada um.

## 2. Configuração — `tests/testenv.lua`

A simples existência do arquivo é a condição para o sistema partir. Campos:

```lua
boot = 'boot.lua'              -- script da fase de boot
testlist = 'lists/scnlist.txt' -- lista de cenários; linhas com '#' são ignoradas
processdump = true             -- mostra o trace do ALVO na tela
testdump = true                -- mostra o log das scripts de teste
emuldump = true                -- mostra o log do sequenciador
msc = true                     -- gera diagrama MSC das trocas
jenkins = false                -- saída para CI (gera test-reports.xml)
```

**Caminhos são relativos a `tests/`**, não à raiz do projeto.

O padrão da ferramenta é `testenv.lua` ser **gerado** — um symlink para um perfil de
`tests/envs/` criado pelo `menutst.sh`. Versionar o `testenv.lua` quebra esse mecanismo: foi
exatamente por isso que, no ctrlic-md, as linhas `ln -s` do `menutst.sh` acabaram comentadas e o
script passou a oferecer um menu que não trocava nada.

## 3. API dos cenários

| Função | Para quê |
|---|---|
| `START()` | ponto de entrada, obrigatório |
| `CLASS(desc)` / `DESCRIPTION(desc)` | classe (exigida pelo jenkins) e descrição |
| `TASKS{ NOME = peer, ... }` | apelida os peers usados |
| `SETCONNECT(peer)` / `SETDISCONNECT(peer)` | forja evento de conexão/desconexão no alvo |
| `SETDATA(data, peer)` | forja recepção de pacote |
| `RPC(data, peer)` | `SETCONNECT` + `SETDATA` |
| `PAC{0x51, 0x00}` | monta pacote binário |
| `NEXT('HANDLER', peer)` | captura o **próximo** pacote que sai do alvo e valida o destino |
| `CATCH('HANDLER', peer)` | captura requisição de conexão vinda do alvo |
| `TIMER(ms, callback)` | timer emulado |
| `LOG(texto)` / `FREEZE()` | trace / congela para depuração |
| `FINISH()` | encerra o cenário com sucesso e libera o próximo |

`NEXT` é o coração: valida **sequência e destino**. Pacote que chega fora de ordem, ou para outro
peer, vira `SEQUENCE ERROR: KEY MISMATCH`.

## 4. As armadilhas que custam tempo

### 4.1. Não existe watchdog — travamento é silencioso

Expectativa não atendida **trava para sempre**, sem mensagem, sem exit code. O processo fica vivo
consumindo quase nada de CPU. É o modo de falha mais caro da ferramenta: parece que "não roda",
quando na verdade está esperando um evento que ninguém vai emitir.

Duas classes distintas, com diagnósticos diferentes:

| Classe | Sintoma no processo | Causa típica |
|---|---|---|
| Evento nunca chega | `do_poll`, CPU baixa mas não zero | `NEXT` esperando pacote que o alvo não emite naquele caminho |
| Loop bloqueado | `futex_wait_queue`, **0%** de CPU | harness do projeto bloqueia a thread principal (mutex) e os timers emulados param junto |

Diagnóstico: `ps -o pid,etime,time -p 1` e `cat /proc/1/wchan` dentro do container.

**Receita do watchdog** — cobre a primeira classe. Vai em `tests/testlib.lua` (arquivo do
projeto), não no submódulo. Implementada e validada no ctrlic-md; três detalhes foram descobertos
por experimento e **sem eles a receita não funciona**:

```lua
WATCHDOG_MS = tonumber(os.getenv('WATCHDOG_MS')) or 10000
local WATCHDOG_S, _seq = math.ceil(WATCHDOG_MS / 1000), 0

-- (1) Tem de ser em setUp(), NAO no corpo do arquivo: loadTest() republica
--     NEXT/TIMER em _G antes de CADA cenario. Wrap no require-time e
--     descartado a partir do 2o cenario, em silencio.
function setUp()
    local _NEXT = NEXT
    NEXT = function(handler, peer)
        _seq = _seq + 1
        local mine = _seq
        local armedAt = os.time()
        local recheck
        recheck = function()
            -- (2) contador de sequencia, nao nome do handler
            if _seq ~= mine then return end
            -- (3) TIMER e fila logica, nao relogio: dispara assim que o loop
            --     fica ocioso, sem conferir se os ms passaram. Reancorar em
            --     os.time() e rearmar, senao derruba cenario legitimo.
            if (os.time() - armedAt) >= WATCHDOG_S then
                error('TRAVOU esperando '..tostring(handler)..' -- evento nunca chegou')
            end
            TIMER(WATCHDOG_MS, recheck)
        end
        TIMER(WATCHDOG_MS, recheck)
        return _NEXT(handler, peer)
    end
end
```

Os três, em detalhe:

1. **`loadTest()` (`luavtest/vumsg.lua`) republica `NEXT`/`TIMER` em `_G` a cada cenário.**
   Sobrescrever uma vez, no `require`, funciona só no primeiro e depois é descartado sem aviso.
   `setUp()` roda após essa republicação, para todo cenário — é o ponto certo.

2. **Contador de sequência, não nome de handler.** Cenários que rearmam o mesmo handler em laço
   (`NEXT('ON_ALARM', TEH)` repetido) dariam falso positivo com comparação de nome.

3. **`TIMER` é fila lógica, não tempo real.** `vrun_pop_timer()` em
   `luavtest/cvrun/vrun_core.c` dispara a cabeça da fila sempre que o loop fica ocioso, **sem
   verificar se os ms declarados passaram**. Um watchdog que seja a única entrada da fila dispara
   quase imediatamente e derruba cenário legítimo. Reancorar contra `os.time()` e rearmar até o
   tempo real passar de fato.

O item 3 vive no submódulo compartilhado, então vale para **qualquer** projeto Dígitro que
construa algo parecido — não é peculiaridade do ctrlic-md.

`error()` dentro de callback de `TIMER` **é** capturado pelo sequenciador (mesmo
`protectedCall`/`killScenario` de qualquer handler), virando `EXCEPTION:[...]` + `FALHA` + exit
1. Confirmado por experimento.

A segunda classe (loop bloqueado) **não** é coberta — o timer do watchdog também não avança.
Para ela, `timeout` externo na invocação, com o log mostrando onde parou.

### 4.2. Timer do cenário vs. bloqueio do harness

Se o harness do projeto bloqueia a thread principal esperando algo (leitura de socket, mutex), os
timers emulados **param**. Qualquer reagendamento do alvo que dependa de timer nunca vence, e o
que seria espera vira deadlock.

Sintoma clássico: o cenário devolve `timers` grandes na resposta (`t2`, `t3`) e o harness captura
antes de a requisição sair. Regra prática: **todo intervalo que o cenário devolve ao alvo tem de
ser menor que a janela em que o harness captura**.

### 4.3. Saída em buffer engana

`stdout` em pipe é bufferizado em blocos. Cenário que não encerra não faz flush, e o log parece
vazio mesmo com o teste rodando. Rode com TTY (`docker exec -t`, `docker run -t`) ou `stdbuf -oL`
antes de concluir que "não roda".

### 4.4. Perfil silencioso esconde o trace do alvo

Perfis com `processdump = false` (tipicamente `summary` e `jenkins`) suprimem o trace do processo
sob teste. Procurar log do alvo neles e não achar **não** significa logger quebrado — significa
perfil errado. Use o perfil verboso para depurar.

### 4.5. Envs de exemplo vêm com `boot.lua` genérico

Os `tests/envs/*.lua` que se copia do README apontam para `boot = 'boot.lua'`. Se o projeto nomeou
o boot de outro jeito, os cinco perfis quebram de uma vez e ninguém percebe, porque o
`menutst.sh` costuma ter as linhas de symlink comentadas por causa disso.

## 5. Como diagnosticar uma suíte que parou de rodar

Sequência que funcionou (ctrlic-md, suíte parada 18 meses):

1. **Rode com TTY** e veja onde para de fato. Sem isso, você depura buffer.
2. **`git log -S '<simbolo>'`** — pickaxe acha quando o evento esperado apareceu ou sumiu do
   código. É o que separa "teste escrito errado" de "código regrediu".
3. **Rode no commit anterior à suspeita**, em worktree separado. Se passa lá e falha aqui, o
   intervalo entre os dois commits contém a causa.
4. **Classifique cada expectativa não atendida**: (a) regressão de código — conserta o código;
   (b) teste escrito para comportamento que nunca existiu — conserta o teste; (c) pré-condição
   faltando — conserta o setup do cenário.
5. **Pré-condição específica de um cenário mora no cenário**, não no boot comum. Boot é o que
   vale para todos.
6. **Rode 5x antes de declarar estável.** Uma execução verde não prova nada: uma fragilidade de
   ~10% passa despercebida e volta a assombrar no CI. Margem apertada contra latência real é a
   causa mais comum.

## 6. Integração com CI

O runner devolve **exit code 0 no sucesso e diferente de 0 na falha** — confirme isso no seu
projeto antes de confiar. O perfil `jenkins` gera `test-reports.xml`. Cuidado com scripts
wrapper que terminam em `exit 0` no ramo de argumento inválido: letra de perfil errada vira CI
verde sem ter rodado teste nenhum.

---

**Implementação de referência**: `ctrlic-md` — ver `ctrlic-md/docs/luavtest.md` para o que é
específico daquele harness (servidor HTTP embarcado em `test-suite.c`, contador de ciclos,
container Rocky 8).
