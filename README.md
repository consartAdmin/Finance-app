# CONSART Financeiro

App Flutter (Android e iOS) para consultar o financeiro do ERP Infinity
(https://erp.consart.com.br), usando as mesmas APIs das telas do ERP.
Versão 1: somente consulta.

## Funções

- Login com o usuário do ERP
- **Contas a pagar** (`/api/accounts-payable`): mês ou período de vencimento,
  situação (pendente, vencido, pago, cancelado), busca por fornecedor, nota,
  documento ou descrição. Totais do filtro (títulos, pago, em aberto) e detalhe
  de cada título.
- **Contas a receber** (`/api/accounts-receivable`): período por vencimento ou
  emissão, situação, conta bancária e busca. Totais e detalhe de cada título.
- **Vendas** (`/api/reports/sales`, o mesmo do Relatório de Vendas): mês atual
  por padrão, filtro de período, vendedor e cliente. Resumo (faturamento,
  notas, itens, lucro bruto), vendas por dia, por cliente, por produto e a
  lista de notas.

## APK

Cada push na `main` gera um APK pelo GitHub Actions. Último APK:
https://github.com/consartAdmin/finance-app/releases/latest/download/consart-financeiro.apk
