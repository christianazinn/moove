P: When moving, the process of sorting through your current items and deciding what to do with 686789them is really tedious

Task breakdown

A. Capture and inventory (start first; everything depends on it)  
1\. LiDAR room scan → 3D room plus a list of objects. Apple's RoomPlan API is worth a look: it returns furniture types and dimensions out of the box.  
2\. Photo capture → item identification. LiDAR can't tell a leather chair from a cheap one. Send photos to a vision model to get the item type, material, brand and condition.  
3\. Inventory data model. Name, category, dimensions, photos, estimated value, keep/sell/donate/trash, fragile flag, "might be sentimental" flag.

B. Pricing and sorting

4\. Price lookup. Pull comparable listings from Marketplace, Craigslist and eBay.  
5\. Automatic sorting. An LLM call or simple rules based on value, condition, size and what it costs to move the item.  
6\. Review screen. A scrollable list where any item can be changed. Possibly sentimental items are flagged for the user to decide, not kept automatically.

C. New home

7\. Zillow listing → floor plan → room dimensions. Riskiest task. Have a backup: type in room dimensions by hand, or hardcode one demo house.  
8\. Arrange kept items in the new floor plan. Offer several layouts.  
9\. "Items fly into the new house" animation. The wow moment for the demo.  
10\. Shopping list for the new home. Ask the user what they need, or generate a starter list.

D. Marketplace agents and payment (top priority)

11\. Marketplace data access. Use a ready-made scraping tool rather than building one, probably Apify, which has scrapers for Craigslist and Facebook Marketplace.  
12\. Sell agent. Writes and posts listings for the "sell" items.  
13\. Buy agent. Finds good deals for the shopping list.  
14\. Fraud screening. Flag prices that are too good to be true, new or empty seller accounts, requests to pay outside the platform, and reused photos.  
15\. Payment through escrow. Pick a provider that has a test (sandbox) mode.  
16\. Security pass. Encrypt user data and keep API keys and passwords out of the repo.

E. Move logistics

17\. Volume → truck count and mover cost estimate. Getting quotes from movers is a known pain point.  
18\. Packing plan. Which items go in which box, keeping fragile items together and grouping by room so unpacking is easy.

F. Team process  
\- Put tasks 1–18 into GitHub issues. Each person claims one, merges it and takes the next.  
\- Use Claude to break down tasks, coordinate who does what and keep branches tidy.

\[00:00\] buddy wait so here's the idea for our logo it's move with two o's and the two o's are tires  
\[00:09\] okay that's it move with two o's why is it two o's because like move with one o is taken  
\[00:22\] what does it mean like why is she so stupid i told you it feels like you're more on the move2  
\[00:27\] there's two o's it's like it's like the the o's like extends like the momentum of the phrase  
\[00:34\] exactly of the word yeah yeah we can have a cow as the logo a cow with wheels wait i'm confused  
\[00:44\] why my mom thinks four people can fit in the threes okay this is just like not true it doesn't matter  
\[00:49\] barely three people can fit in the back of a three person okay um but now she's okay in all seriousness  
\[00:56\] what are the features that we want to um okay so first you scan the room with lidar right with lidar  
\[01:04\] and then it turns it into a digitized version of the room okay and it creates an inventory of inventory  
\[01:11\] of all the objects in the room yeah um and then it looks up uh like all the prices that you can  
\[01:20\] like sell these things for and it will automatically categorize into selling throw away donate it will  
\[01:29\] ask you to pick which one no it will automatically categorize them and then you can scroll through  
\[01:35\] the list and change it right you can manually change stuff yeah so it'll automatically categorize  
\[01:41\] into throwing away uh keeping selling or donating how do we plan to test this um we can have my dad  
\[01:51\] like take lidar off my room and then wait like how does lidar work can you like make a lidar  
\[01:57\] recording yeah yeah okay uh and we can also test it on our hotel room yeah yeah um or just find a  
\[02:05\] random like bring it to someone's house wait yeah so larkin larkin wow and then i guess like it could  
\[02:17\] also identify like potentially sentimental objects and then like have you like force you to manually  
\[02:24\] like decide on those things that's what i was and then like what well i guess i guess if it's  
\[02:32\] sentimental then like automatically doesn't make any sense decides to keep it wait what no but this  
\[02:38\] doesn't so for instance like my desk lamp is very sentimental to me because i've had it for forever  
\[02:42\] but no one knows this right but this is like completely not obvious that's why it's like  
\[02:48\] it's fine if you scroll through things and just change it right wait your desk lamp is not  
\[02:52\] sentimental my desk lamp's really sentimental okay back back let's move back on topic um my point  
\[03:00\] yeah no we can get the user to like manually like to um okay oh also we can like so how is it supposed  
\[03:10\] to categorize things just based on like what it's like make a model wait like like my demo they already  
\[03:20\] how how does it do it you're just sourcing based on like office supplies or like like wall  
\[03:26\] decorations plants um etc i just so i can figure it out i'm sure it's like not that hard but i'm sure  
\[03:32\] there's like a data set out there that like okay has to wait after this oh at this point do we like  
\[03:39\] have a new house like does the person know where no they should like enter a zillow like right yeah  
\[03:45\] wait yeah so they're gonna enter zillow and maybe we'll figure out if we can like map any house  
\[03:51\] well we can get the floor plans of the house right yeah and then from the floor plans of the house  
\[03:56\] you can like rebuild the room yeah exactly and it will like oh it can prompt you to like ask what items  
\[04:05\] you want like or like the general five yeah i mean like generate a list of things and then it will  
\[04:14\] have agents tracking like facebook marketplace or like and then like one tool we can we can develop  
\[04:23\] like a custom tool for the agents but i don't think we should use a custom tool i think we can use one  
\[04:29\] of the track tools okay sure there's like a lot of okay not cartesia what is confusion i don't know  
\[04:37\] it's not right i think you can use apathy because like that's like connected to craig's list and like  
\[04:44\] okay so like the agents search facebook marketplace like look for fraud and then like find the non-frozen  
\[04:49\] of things and then like and the thing that can actually do the payment is like x4 20 or something  
\[04:55\] sure like we need to like make sure like the back end and like all the like we're encrypting stuff and  
\[05:01\] like shit like so it's like secure or i'm sure they care about it and then yeah and then it  
\[05:08\] will like take all the objects right no like put it in your new house x4 the one you keep and the new  
\[05:13\] ones yeah and we can like make a cool visual well all like the items like fly out of your house and  
\[05:18\] like into the new house and then like oh i like that yeah yeah this is gonna be great and then  
\[05:26\] and like it will arrange them like in like multiple ways in your house oh yeah and you can  
\[05:31\] like paper you can i do yeah this just sounds like another app no it's not for us like much simpler  
\[05:40\] it does kind of size for like we don't care ours a little better for us not about moving right  
\[05:45\] bro we just like slap the concept on top of like yeah but this is okay wait wait like we can't  
\[05:52\] wait i think the point is like we came up with this idea about moving like independently  
\[05:58\] true well yeah and then we we saw another app and then like over index on it yeah yeah wait and then we can  
\[06:04\] like prioritize like the financial part yeah the financial part is like more anti-fraud like  
\[06:18\] yeah yeah no we can put this transcript in the cloud and then clouds can like generate like  
\[06:23\] curious like like that are like about you for like yeah and then we also have it coordinate like how to  
\[06:36\] have it decide how to coordinate because it sounds like what you guys did at la hacks wasn't  
\[06:42\] wasn't optimal probably my clock and swept the task i thought it was like fine well yeah it was like  
\[06:51\] somewhat optimal somewhat like we did work on different things yeah anything more to say chat  
\[07:08\] yeah that's it i think what did my dad say my father oh my dad talked about like plumbing and like  
\[07:45\] foundation problems i don't think that's really like yeah it's not really like what are the troubles he  
\[07:51\] have and he's like the neighbors are allowed they do drugs and foundations are found sometimes  
\[08:07\] what did what are your parents are like okay my dad said like yeah getting quotes for like  
\[08:16\] movers um so like wait no i think it's quite similar to what we're doing but like we can also  
\[08:22\] like calculate like the total volume of like the stuff in the house right oh mine are so already  
\[08:26\] does so you calculate like like how many trucks you need in the stuff wait my also like estimates the  
\[08:31\] waivers that's good yeah we should do that okay um said like optimizing what goes into what boxes  
\[08:50\] yeah that facilitates easy unpacking and little damage and like all the like last stuff  
\[08:58\] should like go together wait yes when does like have a fragile wow your parents type so much  
\[09:29\] my dad gave me two sentences christian any other thoughts about what is difficult when moving  
\[09:37\] i haven't moved in the while so i don't know um what is difficult when moving oh like sometimes  
\[09:50\] like like if you have like a large bed right like transporting out of the door is hard  
\[09:55\] it's like maybe you can tell you like how to transport things out of doors and like whether  
\[09:59\] they will like fit in your hallways and stuff just use your brain wait like that couch the couch  
\[10:07\] problem that's why i literally that's literally my closet we're not gonna do that  
\[10:19\] wait like lord right lighter itself will probably not give you like very good  
\[10:39\] representation of like what each thing is like made of like it could be a leather chair  
\[10:44\] and it could be a gold chair and we don't know the difference yeah are you gonna have like a bed  
\[10:48\] with a really fancy like yeah wait we should also like have photos done right yeah  
\[10:58\] and then have also do a light okay yeah we should do but yeah just like give us a better picture of  
\[11:04\] like yeah you can select individual objects yeah yeah yeah wait what can do is like we can  
\[11:13\] split this into like 10 or 20 tasks right and we can each like take a task and we finish it  
\[11:18\] like upload to get and then like take the next task so like it's not yeah yeah so it's not like  
\[11:24\] just four things right because like this could be like bad yeah well really you should just have  
\[11:28\] like your agents um yeah my agents do do my and then organize well they should also organize  
\[11:36\] your branches and then because they probably know more get than you know yeah this is true  
\[11:41\] epsilon is greater than zero or no like and is greater than zero i guess i guess like one other  
\[11:50\] future you could have is just like figuring out who the best mover is like moving company is but like  
\[11:56\] i think this is going to but it's like a little bit irrelevant or we can we can we can like treat it  
\[12:03\] the same as like buying a chair right buying a moving like park and buying a chair is like it's  
\[12:08\] like managing finance yeah yeah you can just like have agents like run around i see the logo  
\[12:20\] is that it yeah sure

| \# | Area | Task | Notes | Owner | Status |
| :---- | :---- | :---- | :---- | :---- | :---- |
| 1 | Setup | Login (Auth0) | Everything else is tied to a logged-in user. |  | To do |
| 2 | Capture and inventory | Inventory data model (SpacetimeDB) | Name, category, dimensions, photos, estimated value, keep/sell/donate/trash, fragile flag, "might be sentimental" flag. Every feature reads and writes this, so pin it down early. |  | To do |
| 3 | Capture and inventory | Record the demo room scan | Use Apple's RoomPlan API (returns furniture types and dimensions). Do it once and everyone has test data. |  | To do |
| 4 | Capture and inventory | Scan upload → item inventory | Needs the scan (\#3) and the data model (\#2). |  | To do |
| 5 | Capture and inventory | Photo → item details | Vision model adds type, material, brand and condition (LiDAR can't tell a leather chair from a cheap one). Pricing depends on this. |  | To do |
| 6 | Pricing and sorting | Pricing agent (Apify) | Pull comparable listings from Marketplace, Craigslist and eBay using Apify scrapers. Needs the inventory (\#4, \#5). |  | To do |
| 7 | Pricing and sorting | Live spending log (x402) | Build right after pricing, since it logs the pricing agent's payments (\#6). |  | To do |
| 8 | Pricing and sorting | Automatic sorting | LLM call or simple rules based on value, condition, size and moving cost. Needs prices (\#6). |  | To do |
| 9 | Pricing and sorting | Review screen with sentimental flags | Scrollable list where any item can be changed; possibly sentimental items are flagged for the user to decide. Needs the sorted list (\#8). |  | To do |
| 10 | Pricing and sorting | Two-screen live sync (SpacetimeDB) | Makes the review screen (\#9) work across two devices. |  | To do |
| 11 | Marketplace and payment | eBay listing agent | Writes and posts listings for the "sell" items. Needs prices (\#6) and sorting (\#8). |  | To do |
| 12 | Marketplace and payment | Phone approval for expensive listings (Auth0) | Sits in front of the eBay posting in \#11. |  | To do |
| 13 | New home | New home floor plan | Start with a hardcoded demo house; add Zillow listing → floor plan later only if there's time (riskiest task). |  | To do |
| 14 | New home | Arrange kept items \+ fly-in animation | Offer several layouts; the fly-in is the demo's wow moment. Needs the floor plan (\#13) and "keep" items (\#8). |  | To do |
| 15 | New home | "Still need to buy" list \+ checkout (Visa) | Ask the user what they need or generate a starter list; buy agent finds deals. Needs the floor plan (\#13) and "keep" items (\#8). |  | To do |
| 16 | Wrap-up | Summary screen | Adds up results from sales, sorting and everything above. |  | To do |
| 17 | Security | Security pass | Encrypt user data; keep API keys and passwords out of the repo. |  | To do |
| 18 | Marketplace and payment | Fraud screening (stretch) | Flag too-good-to-be-true prices, new or empty seller accounts, requests to pay off-platform, and reused photos. |  | To do |
| 19 | Move logistics | Truck and packing plan (stretch) | Volume → truck count and mover cost estimate; which items go in which box, fragile items together, grouped by room. |  | To do |

1\. \#5 Login (Auth0). Everything else is tied to a logged-in user.  
2\. \#4 Inventory data model (SpacetimeDB). Every feature reads and writes this, so pin it down early.  
3\. \#1 Record the demo room scan. Do it once and you have test data for everyone.  
4\. \#2 Scan upload → item inventory. Needs the scan (\#1) and the data model (\#4).  
5\. \#3 Photo → item details. Adds material, brand and condition, which pricing depends on.  
6\. \#6 Pricing agent (Apify). Needs the inventory.  
7\. \#7 Live spending log (x402). Build it right after pricing, since it logs the pricing agent's payments.  
8\. \#8 Automatic sorting. Needs prices to decide keep, sell, donate or trash.  
9\. \#9 Review screen with sentimental flags. Needs the sorted list.  
10\. \#10 Two-screen live sync (SpacetimeDB). Makes the review screen work across two devices.  
11\. \#14 eBay listing agent. Needs prices and the "sell" items.  
12\. \#15 Phone approval for expensive listings (Auth0). Sits in front of the eBay posting from \#14.  
13\. \#11 New home floor plan. Start with the hardcoded demo house, and add Zillow later only if there's time.  
14\. \#12 Arrange kept items \+ fly-in animation. Needs the floor plan and the "keep" items.  
15\. \#13 "Still need to buy" list \+ checkout (Visa). Needs the floor plan and the "keep" items.  
16\. \#16 Summary screen. Needs sales, sorting  because it adds up results from everythingabove.  
17\. \#17 Security pass.  
18\. \#18 Fraud screening (stretch goal).  
19\. \#19 Truck and packing plan (stretch goal)

| \# | Area | Task | Notes | Owner | Status |
| ----- | ----- | ----- | ----- | ----- | ----- |
| 1 | Capture and inventory | LiDAR room scan → 3D room plus a list of objects | Try Apple's RoomPlan API: it returns furniture types and dimensions out of the box. |  | To do |
| 2 | Capture and inventory | Photo capture → item identification | LiDAR can't tell a leather chair from a cheap one. Use a vision model to get type, material, brand and condition. |  | To do |
| 3 | Capture and inventory | Inventory data model | Name, category, dimensions, photos, estimated value, keep/sell/donate/trash, fragile flag, "might be sentimental" flag. |  | To do |
| 4 | Pricing and sorting | Price lookup | Pull comparable listings from Marketplace, Craigslist and eBay. |  | To do |
| 5 | Pricing and sorting | Automatic sorting | LLM call or simple rules based on value, condition, size and what it costs to move the item. |  | To do |
| 6 | Pricing and sorting | Review screen | Scrollable list where any item can be changed. Possibly sentimental items are flagged for the user to decide. |  | To do |
| 7 | New home | Zillow listing → floor plan → room dimensions | Riskiest task. Backup: type in room dimensions by hand, or hardcode one demo house. |  | To do |
| 8 | New home | Arrange kept items in the new floor plan | Offer several layouts. |  | To do |
| 9 | New home | "Items fly into the new house" animation | The wow moment for the demo. |  | To do |
| 10 | New home | Shopping list for the new home | Ask the user what they need, or generate a starter list. |  | To do |
| 11 | Marketplace and payment (priority) | Marketplace data access | Use a ready-made scraping tool, probably Apify, which has scrapers for Craigslist and Facebook Marketplace. |  | To do |
| 12 | Marketplace and payment (priority) | Sell agent | Writes and posts listings for the "sell" items. |  | To do |
| 13 | Marketplace and payment (priority) | Buy agent | Finds good deals for the shopping list. |  | To do |
| 14 | Marketplace and payment (priority) | Fraud screening | Flag prices that are too good to be true, new or empty seller accounts, requests to pay outside the platform, and reused photos. |  | To do |
| 15 | Marketplace and payment (priority) | Payment through escrow | Pick a provider that has a test (sandbox) mode. |  | To do |
| 16 | Marketplace and payment (priority) | Security pass | Encrypt user data and keep API keys and passwords out of the repo. |  | To do |
| 17 | Move logistics | Volume → truck count and mover cost estimate | Getting quotes from movers is a known pain point. |  | To do |
| 18 | Move logistics | Packing plan | Which items go in which box, keeping fragile items together and grouping by room so unpacking is easy. |  | To do |

