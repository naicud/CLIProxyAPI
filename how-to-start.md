# Come avviare CLIProxyAPI in locale con Docker Compose e Supabase Postgres

Questa guida spiega come avviare **CLIProxyAPI in locale con Docker Compose**, usando **Supabase Postgres come storage persistente** tramite `PGSTORE_DSN`, così da poter fare i login OAuth dei provider supportati e usare le funzionalità della proxy CLI.

## Obiettivo dell'architettura

In questa configurazione:

- **CLIProxyAPI gira in locale** dentro Docker Compose.
- **La persistenza reale di configurazione e credenziali** finisce in **Postgres/Supabase**.
- Il container mantiene anche una **copia locale di lavoro** dei file di config e auth, ma con `PGSTORE_DSN` il dato autorevole resta nel database.

In pratica:

- `config_store` contiene la configurazione della proxy.
- `auth_store` contiene i login/token dei provider.
- le tabelle vengono create automaticamente nello schema indicato da `PGSTORE_SCHEMA` (default `public`).

## Cose importanti da sapere prima di partire

1. **Supabase qui viene usato come PostgreSQL compatibile**, non come stack Supabase locale.
2. Se abiliti `PGSTORE_DSN`, il progetto usa il backend Postgres interno e non il semplice storage file-based.
3. In modalità Postgres:
   - la config viene inizialmente bootstrapata nel database;
   - i login salvano i token nel database;
   - una copia locale viene ricreata/sincronizzata dal database.
4. Il bind mount `./auths:/root/.cli-proxy-api` del `docker-compose.yml` è utile soprattutto in modalità file-based. Con `PGSTORE_DSN`, l'auth dir attivo viene reindirizzato verso la workspace interna del Postgres store.

## Prerequisiti

Ti servono:

- Docker
- Docker Compose plugin (`docker compose`)
- un database Supabase/Postgres raggiungibile dall'ambiente Docker locale
- le credenziali degli account/provider che vuoi autenticare

Consiglio anche di avere:

- accesso al **SQL Editor di Supabase** oppure un client Postgres per verificare le tabelle
- una password forte per il pannello management locale

## File coinvolti

Questa guida si basa sui file già presenti nel repository:

- `.env.example`
- `docker-compose.yml`
- `config.example.yaml`

## 1. Prepara l'ambiente locale

Dalla root del progetto:

```bash
cp .env.example .env
mkdir -p logs auths
```

> `auths/` e `logs/` possono restare anche se usi Postgres: non danno fastidio e sono coerenti con il compose esistente.

## 2. Configura `.env`

Apri `.env` e imposta almeno queste variabili:

```env
# Abilita il management locale (consigliato per gestire config e auth in modo semplice)
MANAGEMENT_PASSWORD=una-password-molto-forte

# Storage persistente su Supabase/Postgres
PGSTORE_DSN=postgresql://postgres.<project-ref>:<password-url-encoded>@<host-o-pooler>:5432/postgres?sslmode=require
PGSTORE_SCHEMA=public
PGSTORE_LOCAL_PATH=/var/lib/cliproxy
```

### Note importanti sul DSN Supabase

- usa il DSN reale del tuo progetto Supabase;
- nella maggior parte dei casi è corretto mantenere `sslmode=require`;
- se la password contiene caratteri speciali, **URL-encodala**;
- se usi il pooler Supabase, la porta potrebbe essere diversa da `5432`: usa i valori mostrati dal tuo progetto.
- la workspace locale del Postgres store verra creata sotto `PGSTORE_LOCAL_PATH/pgstore`.

### Variabili utili ma opzionali

Puoi aggiungere anche:

```env
CLI_PROXY_PORT=8317
CLI_PROXY_ENV_FILE=.env
```

Se vuoi lavorare con il pannello management solo in locale, `MANAGEMENT_PASSWORD` basta: non serve impostare `remote-management.secret-key` nel file YAML per questa guida.

## 3. Scegli come inizializzare la configurazione

Qui c'e il punto piu importante della guida.

Con `PGSTORE_DSN` attivo, la configurazione runtime viene letta dal **Postgres store**. Al primo bootstrap, il database viene inizializzato partendo dal template `config.example.yaml` copiato nell'immagine/container.

Questo significa che hai due strade:

### Opzione A - consigliata: avvio rapido + modifica dal pannello management

Usa subito Docker Compose, poi aggiorna la config dal pannello management locale.

Vantaggi:

- piu semplice;
- non richiede rebuild iniziale;
- le modifiche vengono salvate nel config store Postgres.

### Opzione B - seed iniziale personalizzato

Se vuoi che il **primo bootstrap** del database parta gia da una config custom:

1. modifica `config.example.yaml` nel repository;
2. costruisci l'immagine localmente;
3. avvia i container.

> In modalita `PGSTORE_DSN`, il mount verso `/CLIProxyAPI/config.yaml` non e il file principale usato per il bootstrap del Postgres store. Il bootstrap usa il template `config.example.yaml`, poi la config runtime viene gestita nella workspace interna sincronizzata col database.

## 4. Avvia CLIProxyAPI con Docker Compose

### Modalita rapida con immagine prebuilt

```bash
docker compose up -d --no-build
```

### Modalita sviluppo locale da sorgente

```bash
docker compose build
docker compose up -d --remove-orphans --pull never
```

### Verifica che il container sia partito

```bash
docker compose ps
docker compose logs -f cli-proxy-api
```

Se tutto e corretto, l'API espone la porta principale:

- `http://localhost:8317`

e il compose pubblica anche porte utili per alcuni callback OAuth:

- `8085` per Gemini
- `1455` per Codex
- `54545` per Claude
- `51121` per Antigravity
- `11451` per iFlow

## 5. Primo accesso e gestione locale

Se hai valorizzato `MANAGEMENT_PASSWORD`, puoi aprire:

```text
http://localhost:8317/management.html
```

Usa quella password per entrare.

### Perche conviene attivarlo in questa guida

Con storage Postgres, il pannello management e il modo piu semplice per:

- modificare la config effettiva usata dalla proxy;
- verificare le auth salvate;
- lavorare sulla config persistita nel database, non su un file temporaneo.

## 6. Sistema la configurazione applicativa

Dopo il primo avvio, verifica la config attiva e correggi soprattutto questi punti:

### API keys della proxy

Nel template di esempio esistono chiavi placeholder:

```yaml
api-keys:
  - "your-api-key-1"
  - "your-api-key-2"
  - "your-api-key-3"
```

Sostituiscile con valori reali oppure riduci la lista a una sola chiave forte, per esempio:

```yaml
api-keys:
  - "cliproxy-local-dev-key"
```

Questa chiave ti servira per chiamare gli endpoint `/v1/*`.

### Host e porta

I valori di default vanno bene per questa guida:

```yaml
host: ""
port: 8317
```

### Management remoto

Per uso locale va bene lasciare:

```yaml
remote-management:
  allow-remote: false
```

## 7. Esegui i login dei provider

Con il server gia in esecuzione, fai i login direttamente dentro il container.

### Comandi principali

```bash
docker compose exec cli-proxy-api ./CLIProxyAPI -login -no-browser
docker compose exec cli-proxy-api ./CLIProxyAPI -codex-login -no-browser
docker compose exec cli-proxy-api ./CLIProxyAPI -codex-device-login
docker compose exec cli-proxy-api ./CLIProxyAPI -claude-login -no-browser
docker compose exec cli-proxy-api ./CLIProxyAPI -qwen-login
docker compose exec cli-proxy-api ./CLIProxyAPI -iflow-login -no-browser
docker compose exec cli-proxy-api ./CLIProxyAPI -iflow-cookie
docker compose exec cli-proxy-api ./CLIProxyAPI -antigravity-login -no-browser
docker compose exec cli-proxy-api ./CLIProxyAPI -kimi-login
```

### Quando usare `-no-browser`

Dentro Docker e la scelta piu sicura, perche evita il tentativo di aprire il browser dal container. In quel caso:

- il comando ti mostra l'URL o le istruzioni di login;
- completi l'autenticazione dal browser della tua macchina;
- il callback torna sulle porte pubblicate da Docker Compose, se il provider usa una redirect locale.

### Flag utili

Puoi usare anche:

```bash
docker compose exec cli-proxy-api ./CLIProxyAPI -login -project_id <PROJECT_ID> -no-browser
docker compose exec cli-proxy-api ./CLIProxyAPI -claude-login -oauth-callback-port 54545 -no-browser
```

I flag supportati includono:

- `-project_id` per Gemini
- `-oauth-callback-port` per forzare una porta callback
- `-no-browser` per login manuale

## 8. Verifica che i dati vadano davvero su Supabase/Postgres

Una volta avviato il servizio e completato almeno un login, verifica nel database.

### Config salvata

Nel SQL editor di Supabase:

```sql
select id, updated_at
from public.config_store;
```

Dovresti vedere almeno una riga con:

- `id = 'config'`

### Auth salvate

```sql
select id, updated_at
from public.auth_store
order by updated_at desc;
```

Dovresti vedere una o piu righe relative ai provider autenticati.

> Se hai impostato `PGSTORE_SCHEMA` diverso da `public`, sostituisci `public` nelle query.

## 9. Verifica che la proxy funzioni davvero

### Test base dell'endpoint root

```bash
curl http://localhost:8317/
```

### Lista modelli

Usa una delle API key configurate nella proxy:

```bash
curl http://localhost:8317/v1/models \
  -H "Authorization: Bearer cliproxy-local-dev-key"
```

Oppure:

```bash
curl http://localhost:8317/v1/models \
  -H "X-Api-Key: cliproxy-local-dev-key"
```

Se hai completato correttamente i login, qui vedrai i modelli disponibili dei provider autenticati.

### Chiamata OpenAI-compatible di esempio

Sostituisci `<MODELLO_REALE>` con uno dei modelli restituiti da `/v1/models`:

```bash
curl http://localhost:8317/v1/chat/completions \
  -H "Authorization: Bearer cliproxy-local-dev-key" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<MODELLO_REALE>",
    "messages": [
      {
        "role": "user",
        "content": "Rispondi con ok"
      }
    ]
  }'
```

Se la risposta arriva correttamente, allora:

- il container e attivo;
- la proxy accetta richieste;
- l'autenticazione locale della proxy funziona;
- almeno un provider autenticato e utilizzabile;
- i dati di config/auth sono coerenti col backend Postgres.

## 10. Dove finiscono davvero i dati

Con questa configurazione i dati vivono in piu posti, ma non hanno tutti lo stesso ruolo:

### Postgres/Supabase

E il livello **autorevole** quando `PGSTORE_DSN` e attivo:

- `config_store`
- `auth_store`

### Workspace locale interna del container

Serve come mirror operativo del Postgres store:

- config locale generata dal backend
- auth locali sincronizzate dal backend

Se il container riparte, queste copie possono essere ricreate dal database.

### Cartelle bind-mount del compose

- `./logs` resta utile per i log
- `./auths` non e la fonte principale delle auth quando usi `PGSTORE_DSN`

## 11. Flusso consigliato, in breve

Se vuoi la sequenza piu semplice e affidabile:

1. copia `.env.example` in `.env`
2. imposta `PGSTORE_DSN`, `PGSTORE_SCHEMA` e `MANAGEMENT_PASSWORD`
3. avvia con `docker compose up -d --no-build`
4. entra nel management locale su `http://localhost:8317/management.html`
5. sostituisci le API key placeholder nella config
6. esegui i login dei provider via `docker compose exec ...`
7. verifica `/v1/models`
8. verifica in Supabase che `config_store` e `auth_store` vengano popolati

## 12. Troubleshooting rapido

### Il container parte ma `/v1/models` risponde con errore di autenticazione

Controlla:

- di aver sostituito le `api-keys` placeholder;
- di usare davvero una chiave presente nella config attiva;
- di non stare modificando solo un file locale non piu usato dalla runtime Postgres-backed.

### Il login OAuth non completa il callback

Controlla:

- che Docker Compose abbia esposto le porte callback richieste;
- che tu stia usando `-no-browser` se lavori dentro container;
- che firewall o altri processi locali non stiano occupando la porta callback.

### Nel database non compaiono dati

Controlla:

- `PGSTORE_DSN`
- `sslmode=require` se necessario per Supabase
- credenziali corrette
- schema corretto in `PGSTORE_SCHEMA`
- log del container con `docker compose logs -f cli-proxy-api`

### Ho cambiato `config.example.yaml` sul mio host ma la proxy non cambia comportamento

E normale se hai gia attivato `PGSTORE_DSN` e il database e gia stato bootstrapato. Dopo il primo bootstrap, la config runtime viene letta dal Postgres store e dalla sua workspace interna, non dal file host che stai guardando.
