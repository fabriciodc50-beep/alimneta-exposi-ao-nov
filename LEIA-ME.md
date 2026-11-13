# Universo Criativo — Lanche coletivo da exposição

## Dois endereços, dois tipos de acesso

- **`index.html` — Participante:** É o ÚNICO endereço que deve ser enviado no grupo do WhatsApp. Escolher alimento, registrar refrigerante de 2 L (com exceção para irmãos), incluir materiais extras, informar nome, quantidade e confirmar. Não existe menu de administrador nessa página e o público não consegue consultar nomes de outras pessoas.
- **`admin.html` — Organizador:** Link reservado ao responsável. Lista nominal, conferência de chegada, confirmação do recebimento de cada item, metas ajustáveis, estatísticas e exportação CSV.

**Atenção:** esconder um link não é segurança. A proteção real do painel online vem da autenticação e das regras RLS do banco Supabase. A versão demonstrativa NÃO é uma área de gestão segura e seus dados não são sincronizados entre celulares.

## Experimentar antes de publicar

- Abra `participante-demo.html` para testar o fluxo do público.
- Abra `organizador-demo.html` para conhecer a gestão.
- Sem Supabase conectado, o navegador armazena dados **localmente no mesmo site/origem**. Não use esse modo para inscrições reais ou divulgação a participantes em aparelhos diferentes.
- Os arquivos de demonstração são independentes e podem ser abertos individualmente. Para testar dados em conjunto no mesmo navegador, é mais confiável rodar os arquivos do projeto em um servidor local ou publicar todos em GitHub Pages, antes de ativar o Supabase.

## Publicação online com GitHub Pages + Supabase

1. Crie um **novo projeto Supabase específico para a exposição** (recomendado) ou use um projeto existente com cuidado. O SQL usa tabelas com prefixo `uc_` para evitar colisões.
2. No **SQL Editor**, execute `schema.sql`. Ele cria 135 itens, os registros e as restrições de acesso.
3. Em **Authentication > Providers**, habilite **Anonymous Sign-ins**. Isso permite cadastrar pelo celular sem pedir e-mail ou senha. Essas sessões são anônimas para o participante, mas autenticadas no backend.
4. Em **Authentication > Users**, crie ou convide o usuário administrativo usando um e-mail e senha que você controla.
5. No SQL Editor, cadastre o seu usuário como administrador (troque pelo e-mail verdadeiro):

```sql
insert into public.uc_admins(user_id)
select id from auth.users where email='seu-email@exemplo.com'
on conflict do nothing;
```

6. Na área **Project Settings / API Keys**, obtenha a **Project URL** e a **publishable key** (pública). No arquivo `config.js`, preencha `supabaseUrl` e `supabasePublishableKey`. **NUNCA** insira uma secret key ou `service_role` no HTML ou JavaScript público.
7. Envie `index.html`, `admin.html`, `app.js`, `styles.css`, `catalogo.js`, `config.js` e a pasta `assets` ao repositório GitHub. Em **Settings > Pages**, publique a pasta raiz da branch principal.
8. Compartilhe no grupo **somente a URL de `index.html`**. Guarde a URL de `admin.html` para você: o acesso real a esse painel exige e-mail e senha do organizador.

## O que o sistema faz

**Participante:** três etapas, catálogo pesquisável de 100 alimentos baratos, refrigerante de 2 L, exceção de irmãos, bebidas alternativas só quando não pode tomar refrigerante, 32 materiais de apoio opcionais com quantidade e confirmação de inscrição. Pode inscrever mais uma pessoa no mesmo aparelho e editar a escolha antes da chegada.

**Organizador:** quantidade de inscritos e presentes, conferência do que foi efetivamente entregue, metas de mesas, copos, gelo e cooler, configuração de data/local/abertura de inscrições, relatório CSV para Excel e atualização automática enquanto a conferência estiver aberta (a cada 20 segundos).

## Regras do lanche coletivo

- Cada participante leva **um item de comida, um refrigerante de dois litros e dinheiro para o sorvete**.
- **Irmãos podem combinar uma única garrafa de 2 L**, indicando quem ficará responsável.
- Quem não pode tomar refrigerante pode selecionar água ou suco.
- Refrigerantes podem ser comprados gelados na sorveteria.
- Mesas dobráveis, toalhas, gelo, cooler, copos, pratos, talheres, facas, utensílios e limpeza ficam na seção opcional de apoio.
- **Tudo que for levado será compartilhado** na mesa coletiva.

## Privacidade e funcionamento

- A página pública não consulta a lista de todos os participantes; consulta somente o próprio cadastro e totais agregados por item.
- Os nomes, detalhes pessoais e confirmações de entrega têm leitura restrita no Supabase por RLS, e a confirmação final é protegida por autorização no banco.
- Não há garantia de segurança dos dados se você publicar somente os arquivos HTML sem instalar o schema e configurar o Supabase.
- Usuários anônimos perdem acesso à própria inscrição se limparem dados do navegador ou usarem outro aparelho; o organizador ainda verá o cadastro e poderá conferir a entrega.
- Ainda é necessário **validar o ambiente online completo** depois de configurado: o teste realizado aqui foi o fluxo local em navegador, não a sincronização real entre aparelhos.

## Arquivos

- `index.html`: interface do participante.
- `admin.html`: interface do organizador.
- `app.js`, `styles.css`: funcionalidades e visual.
- `catalogo.js`: sugestões econômicas e itens de apoio.
- `schema.sql`: banco de dados e autorização.
- `config.js`: URL e chave pública Supabase.
- `assets/capa.webp`: fotografia de capa.
