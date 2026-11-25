# Projeção Vitalícia · Tesouro RendA+

Simulador nativo para macOS. Na primeira abertura, o cenário de exemplo mostra dois aportes hipotéticos de R$ 100 mil cada, em RendA+ 2055 e 2060, ambos a IPCA + 7,5% a.a. Os aportes são editáveis e ficam salvos no próprio Mac. Cada cenário novo começa com R$ 0 investido.

## Instalar

Baixe `Projecao-Vitalicia-macOS.zip` nas [releases](https://github.com/edu-tmrw/projecao-rendaplus/releases/latest), descompacte e mova **Projeção Vitalícia.app** para Aplicativos. O pacote é universal, para Macs Intel e Apple Silicon com macOS 14 ou posterior.

O pacote tem assinatura local e não foi notarizado pela Apple. Se o macOS impedir a abertura, a opção **Abrir Mesmo Assim** pode aparecer em **Ajustes do Sistema → Privacidade e Segurança** após a primeira tentativa. [Instruções da Apple](https://support.apple.com/pt-br/102445)

## Simular

1. Clique em **Simular aporte** e informe o ano de início da renda, a data, o preço e a taxa. Escolha o valor do aporte ou a quantidade de títulos.
2. Use **Atualizar cotações** para buscar preços e taxas de compra no Tesouro Transparente. A cotação pode preencher um novo aporte e os aportes salvos mantêm as premissas registradas.
3. Ajuste o **IPCA anual**, alterne entre **Dinheiro de hoje** e **Dinheiro de amanhã** e compare opções pelo menu de cenários. Abra um ano em **Fluxo por período** para ver os meses.

O card **Carteira genérica** simula uma reserva complementar na mesma tela. Quando **Renda líquida constante** está ativa, o valor do card soma a carteira e o RendA+ no início das retiradas da carteira. O total segue a moeda e o filtro de IR selecionados. A data de nascimento é opcional e permite estender a projeção até os 100 anos.

Cada título tem 240 parcelas mensais. O fluxo é estimado a partir das premissas informadas e inclui IR regressivo sobre rendimentos. Custódia e taxas da corretora ficam fora do cálculo. [Metodologia do Tesouro Direto](https://www.tesourodireto.com.br/documents/d/guest/tesouro_renda_mais)

## Compilar

Com Xcode e o SDK para macOS instalados, execute `swift test` e `./scripts/package-macos.sh`. O ZIP fica em `dist/`.
