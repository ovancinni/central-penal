# Central Penal — FiveM

Primeira versão web responsiva para registro de prisões fictícias de personagens do FiveM, com equipe, fotos, remuneração fixa e fechamento manual.

## O que já está implementado
- Login individual por e-mail e senha.
- Perfis de policial e administrador.
- Painel com totais, prisões recentes e desempenho da equipe.
- Cadastro de prisão com nome, ID/passaporte, crimes, condenação, descrição e foto.
- Fotos em bucket privado (máximo 8 MB; JPEG, PNG ou WebP).
- Valor por prisão definido no banco de dados (inicial: R$ 200.000).
- Financeiro por policial e fechamento manual por intervalo de datas.
- Histórico de fechamentos.
- Políticas RLS no banco e permissões de administrador.

## Publicar online (Supabase + Netlify)

### 1. Criar o banco Supabase
1. Crie um projeto em https://supabase.com/.
2. Abra **SQL Editor** → **New query**.
3. Cole todo o conteúdo de `schema.sql` e execute.
4. Em **Project Settings → API**, copie **Project URL** e **anon/public key**.

### 2. Configurar o site
1. Abra `config.js`.
2. Substitua `COLE_A_URL_DO_SUPABASE_AQUI` pela Project URL.
3. Substitua `COLE_A_CHAVE_ANON_PUBLIC_AQUI` pela chave anon/public.
4. Não use nem publique a chave `service_role`.

### 3. Criar o primeiro administrador
1. No Supabase, abra **Authentication → Users → Add user**.
2. Crie o usuário com e-mail e senha fortes.
3. Abra **SQL Editor** e execute, trocando o e-mail:

```sql
update public.profiles
set role='admin', display_name='Administrador'
where email='SEU_EMAIL_AQUI';
```

4. Crie os demais usuários em **Authentication → Users → Add user**. Eles serão criados como `officer` automaticamente.
5. Ajuste o nome de exibição em **Table Editor → profiles**. Para dar acesso administrativo, altere `role` para `admin` somente a pessoas autorizadas.

### 4. Publicar o site
1. Crie uma conta em https://www.netlify.com/.
2. Descompacte esta pasta e arraste a pasta `central-penal` para a área de deploy manual do Netlify (ou conecte um repositório Git).
3. O Netlify fornecerá um endereço HTTPS compartilhável. Envie esse endereço à equipe.

## Fechamento financeiro
Na tela Financeiro, um administrador informa data inicial e final. O banco cria um fechamento e vincula todas as prisões ainda pendentes dentro desse intervalo. O sistema mantém o histórico e impede fechar duas vezes o mesmo intervalo exato.

## Segurança e observações importantes
- O projeto foi pensado para dados de personagens e ocorrências fictícias do FiveM. Não insira dados pessoais reais, documentos, fotos de pessoas reais ou informações operacionais de segurança pública.
- A chave `anon/public` pode ficar no navegador porque as tabelas e o bucket usam políticas RLS. A chave `service_role` nunca deve ser colocada no site.
- O protótipo não é um sistema oficial nem substitui sistema institucional.
- O fechamento cria o demonstrativo de valores, mas não realiza transferência de dinheiro do servidor. O pagamento deve ser confirmado pela administração.
- Para evitar abuso, convide somente membros conhecidos, use senhas fortes e remova acessos quando alguém sair da equipe.
