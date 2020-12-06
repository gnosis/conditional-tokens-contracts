Future Money
============

"Transferring" money from the future (actually something mathematically equivalent to
it as the market's predictions approach the future reality well enough and the traders
strive for their profit - TODO: prove) is implemented by the contract
`ConditionalTokensMany`.

So, one could pay his tution fees from his future salary!

This contract implements multiple markets with an unlimited number of conditions, but
without splitting and merging.

Anyone can create a market and be its oracle.

Anyone can register as a customer for any market. When somebody registers as a customer
he is provided with 1000 conditonal tokens on the condition denoted by his Ethereum address.
So he may bid on his own condition or sell the tokens.

This is useful when customers are participants of some competition and the price of their
conditional tokens to be depended on their competition score.
