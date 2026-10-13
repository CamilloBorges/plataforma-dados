-- Estoque diário com o custo comercial do dia, calculado pela função do Logus (a mesma que o
-- dataflow "EstoqueDiario Logus" do Fabric usa). Fica em raw_logus.estdiapr.val_custo_coml.
SELECT a.*,
       estmovccusto_coml(a.cdg_filial, a.cdg_produto, a.dat_movimento) AS val_custo_coml
  FROM estdiapr a
