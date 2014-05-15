CommodityStats
==============
###Introduction
Commoditystats is a tool for tracking the price history of buy- and sell-orders on the Commodity Exchange, so that information can be used to your advantage. It does so by saving the statistics as often as once every hour and present them to you in a nice graph. It has a scan button to perform a (fast!) scan of all commodity items and a history link on every presented commodity item.
It currently features:
* Save the price history of buy/sell orders
* Save the history on completed/expired commodity orders
* Display history graphs and a list of past transactions + total profit for individual items
* Show estimated profit for commodity items
* Autofill the best price for buy/sell transactions
* Reuse the price/quantity of the most recently created buy/sell order
* Save the position of the Carbine Commodity window.
* Save the scrollbar position between transactions
* Replace the 4-second blocking confirm/error window with a non-blocking alertbox

###How to use?
Just install the addon and you are done. Additionally, you can type /commoditystats to change a few settings. Commoditystats will gather/save statistics on 2 occasions:
* Simply by browsing the Commodity Exchange. Every item displayed will be saved.
By using the Scan button. Commoditystats will then request every item of every category. Since this takes a few seconds at most, this is the recommended way.
* When browsing the Commodity exchange you will see that an extra history button has been added on every item. Click it to display a graph with the price history for that item. The first time you use this, it won't be very exciting since 1 price point results in a very empty graph. As soon as you got 2 timestamps though (differing by hour), statistics should show.