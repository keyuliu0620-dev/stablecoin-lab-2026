# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer:
The current design creates a centralization risk because the vault holds `MINTER_ROLE`, and the `burn(address from, uint256 amount)` function uses this role for authorization. This means the vault can burn tokens from any user's balance without the user's approval. If the vault contains a vulnerability or an attacker gains control of its execution, users could lose their sUSD without their consent.

To remove this risk, I would separate minting permission from burning permission. In `SimpleStablecoin`, I would keep `MINTER_ROLE` for authorized minting, but change the burning mechanism so that users can burn their own tokens. I could also implement an allowance-based `burnFrom` function, which allows a contract to burn tokens from a user only after the user has approved the required amount.

In `Vault`, the `redeem` function would require the user to authorize the repayment amount. The vault could then use `burnFrom` to burn the approved sUSD before returning the corresponding collateral. The vault would no longer have unrestricted power to destroy any user's balance.

This design follows the principle of least privilege: each contract should have only the permissions necessary to perform its intended function. It reduces the risk of unauthorized token destruction while preserving the deposit-and-redeem mechanism.
<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer:
In a production stablecoin system, I would separate administrative, minting, and pausing permissions instead of assigning all of them to one address. Giving one account every role creates a single point of failure. If that account is compromised, an attacker could grant themselves additional permissions, mint tokens, or freeze the entire system.

I would assign `DEFAULT_ADMIN_ROLE` to a multisignature wallet controlled by several trusted team members. Important administrative actions would require approval from multiple signers rather than one person. I would assign `MINTER_ROLE` to a dedicated minting contract or a tightly controlled operational account. The minting process should also enforce limits and verify that newly issued tokens are adequately backed by collateral.

I would assign `PAUSER_ROLE` to a separate emergency security team or a dedicated security multisignature wallet. This team could pause the system quickly if an exploit or other serious threat were detected. However, unpausing should require stronger review to prevent an attacker from restoring normal operations prematurely.

Finally, I would monitor privileged actions through on-chain events and regularly review role assignments. These measures reduce the risk of a single compromised account controlling the entire stablecoin system. They also improve accountability and make emergency response more reliable.

Overall, separating roles follows the principle of least privilege and reduces operational and security risks.
<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer:
In the current implementation, the `_update` function in `SimpleStablecoin` uses the `whenNotPaused` modifier. Since ERC-20 transfers, minting, and burning all use `_update`, pausing the contract blocks all these operations, including redemption.

To allow redemption during a pause, I would separate the controls for ordinary transfers and redemption instead of applying the same restriction to every balance change. One approach is to implement a transfer-specific pause check that blocks ordinary transfers while allowing authorized minting and burning under controlled conditions.

I would also modify the `redeem` function in `Vault` so that it can operate during a transfer pause, while still checking that the user owns enough sUSD and that the vault holds sufficient collateral. The redemption process should burn only the caller's tokens or tokens explicitly authorized by the caller, then return the corresponding collateral.

However, allowing all burns during a pause could introduce security risks. I would therefore distinguish user-authorized redemption burns from other token operations and apply appropriate access controls. Minting should remain disabled during an emergency unless there is a clearly justified reason to permit it.

This design allows users to exit the system during a crisis while limiting ordinary token transfers. The exact implementation would need additional tests to verify that transfers remain blocked, legitimate redemption succeeds, and unauthorized token destruction is still prevented.
<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer:
The 2008 Reserve Primary Fund crisis and the 2023 USDC depeg show how redemption availability affects confidence during financial stress. In 2008, the Reserve Primary Fund suffered losses after Lehman Brothers failed, causing its net asset value to fall to approximately $0.97 per share. The fund suspended redemptions to avoid selling assets under pressure and to manage its remaining liquidity. However, investors could no longer access their money immediately, which increased uncertainty and highlighted the risks of a financial product that was expected to maintain a stable value.

In March 2023, USDC temporarily traded below $1 after Circle disclosed that $3.3 billion of its reserves were held at Silicon Valley Bank. Concerns about access to those reserves, combined with the weekend closure of banking services and interruptions to primary-market redemption operations, increased selling pressure on secondary markets. USDC recovered its peg after authorities announced that SVB depositors would be protected and banking operations resumed.

These events show that redemption is important for maintaining confidence in a stable-value asset. Keeping redemption available can help arbitrageurs exchange tokens for their underlying value and reduce deviations from the peg. However, redemption also requires sufficient liquid reserves and functioning payment infrastructure. Suspending redemption may provide time to manage a crisis, but it can undermine confidence and increase selling pressure.

For a stablecoin, I would aim to preserve controlled and transparent redemption during a crisis whenever reserves and operations permit. Emergency restrictions should be clearly justified, limited, and communicated to users.
<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer:
A stablecoin can depeg when its market price moves away from its intended value of one US dollar. There are several possible causes, and they do not all affect the collateral invariant in the same way.

The first class of causes is a technical or accounting failure in the on-chain system. For example, a vulnerability in the minting mechanism could allow an attacker to mint tokens without depositing sufficient collateral. If the attacker creates more sUSD than the vault holds in collateral, the invariant `totalCollateral() >= totalSupply()` is violated. Users may lose confidence because the tokens are no longer fully backed.

The second class is an external market or liquidity problem. For example, users may become concerned about the issuer, the availability of reserves, or the ability to redeem their tokens. They may sell sUSD rapidly, causing its market price to fall below one dollar. In this situation, the invariant may still hold because the vault's on-chain collateral and token supply have not necessarily changed. The price can depeg even when the accounting relationship remains correct.

A third possible cause is a loss in the value or availability of off-chain reserves. In a real-world asset-backed stablecoin, bank failures, custody problems, or illiquid assets can undermine confidence in redemption. The on-chain contract may still report sufficient collateral if it cannot observe the actual condition of those off-chain assets.

Therefore, the invariant is necessary but not sufficient for maintaining a stable peg. It can detect certain on-chain backing failures, but it cannot guarantee market liquidity, redemption availability, or the real-world value of collateral.
<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer:
If an attacker obtains `MINTER_ROLE`, they can call `SimpleStablecoin.mint()` and create 1,000,000 sUSD without depositing any collateral. This bypasses the intended deposit-and-mint process and increases the token supply without increasing the vault's collateral.

The attacker could then attempt to redeem the newly minted tokens through `Vault.redeem()`. If the vault contains sufficient collateral and the attacker satisfies the redemption requirements, the vault would burn the attacker's sUSD and transfer the same amount of collateral to them. Since the tokens were created without a corresponding deposit, this would allow the attacker to extract existing collateral that should back other users' tokens. If the vault does not hold enough collateral, the redemption may fail or be limited by the available balance.

The main preventive step is to restrict `MINTER_ROLE` to trusted, carefully controlled contracts or accounts. In this lab, the vault is granted this role so that it can mint tokens after receiving collateral. However, granting the role to an untrusted account would allow that account to bypass the vault's checks.

I would also enforce least-privilege access control, use a multisignature wallet for administrative role management, and monitor role changes and minting activity. A stronger design would ensure that minting can only occur through verified collateral deposits and that the total supply remains backed by collateral. These controls reduce the risk of unauthorized issuance and collateral theft.
<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer:
If the collateral were US Treasuries instead of MockUSDC, the invariant `totalCollateral() >= totalSupply()` could not be implemented in exactly the same simple way. In the current lab, `totalCollateral()` reads the vault's on-chain token balance. The contract can directly verify how many units of MockUSDC it holds.

US Treasuries, however, are real-world financial assets that usually exist in traditional custody and settlement systems rather than directly inside a smart contract. The blockchain cannot automatically verify the actual ownership, market value, or availability of these assets. Therefore, the system would need a reliable way to represent and verify off-chain holdings.

One approach would be to use tokenized Treasury funds or other regulated tokenized securities as collateral. The vault could then read the on-chain balance of these tokens, although it would still need to consider whether the tokens accurately represent the underlying assets and whether redemption is available.

Another approach would involve an external attestation or oracle that reports the value of the Treasury holdings. This introduces additional risks, including inaccurate reports, outdated valuations, custody failures, and delays in updating prices. Treasury values can also change with interest rates, and the assets may not be immediately liquid during periods of market stress.

Therefore, the invariant would need to compare the value of verified collateral against the stablecoin supply, rather than simply comparing token balances. Independent audits, reliable custodians, valuation mechanisms, and legal protections would also be necessary. Even then, the invariant could not guarantee that the underlying assets were always immediately redeemable for cash.
<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer:
A physical building cannot be deposited directly into a smart contract because ownership of real estate is recorded through legal documents and property registration systems. To use a building as collateral for a stablecoin, I would need to connect the legal ownership of the property with an on-chain representation of its value and ownership rights.

One possible approach would be to establish a special purpose vehicle (SPV) that legally owns the building. The SPV could issue tokens representing shares or defined economic interests in the property. These tokens could then be used as collateral in a smart contract, provided that the legal structure permits this arrangement and the tokens represent enforceable rights.

Several off-chain roles would be necessary. A property valuer would estimate the building's market value, while a legal team would verify ownership, liens, mortgages, and compliance with relevant property and securities laws. A regulated custodian or property manager could oversee the asset, and an independent auditor could periodically verify the SPV's financial and legal status. The system would also need a reliable process for handling rental income, maintenance costs, insurance, taxes, and eventual property sales.

An oracle or authorized reporting mechanism could provide updated valuation information to the blockchain. However, property valuations are not continuous, and a building cannot necessarily be sold quickly at its estimated market value. The vault would therefore need conservative collateral ratios, valuation updates, and liquidation procedures that reflect these limitations.

In conclusion, tokenization can connect real estate with blockchain-based finance, but a token alone does not guarantee legal ownership or liquidity. Effective legal enforcement, transparent valuation, reliable custody, and clear redemption rights are essential for a secure real-world asset-backed stablecoin.
<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | `test_Ex4_Mint_RevertsForNonMinter` |
| Transfers revert while paused | `test_Ex4_Pause_BlocksTransfers` |
| **Redemption** reverts while paused | `test_Ex4_Pause_BlocksRedeem` |
| An attacker cannot burn someone else's balance | `test_Ex4_AttackerCannotBurnOthersBalance` |
| ...but the vault holding `MINTER_ROLE` can | `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> **Scenario:** An unauthorized account attempts to grant itself `MINTER_ROLE`.
>
> **Proposed test function:** `test_Ex4_NonAdminCannotGrantMinterRole`
>
> **Reason:** If an attacker could grant themselves `MINTER_ROLE`, they could mint sUSD without depositing collateral. This would undermine the collateral backing and could allow the attacker to extract assets from the vault. The test should verify that an unauthorized account cannot grant roles and that the transaction reverts with the expected access-control error.
