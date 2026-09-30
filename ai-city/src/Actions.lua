-- Actions (ModuleScript) — ReplicatedStorage.Shared.Actions
-- Everything citizens can be seen doing: typing at a desk, lifting weights,
-- cooking, reading, fishing, swinging... The server sets a citizen's "Action"
-- attribute; every player's client plays the pose and adds the props, so it
-- looks smooth and costs the server nothing.
--
-- Each action: Pose (see CityClient's pose library), Props (things held),
-- Seated / Lying (how the server places the body), Label (for nameplates).

local Actions = {}

Actions.List = {
	-- work
	type = { Pose = "type", Seated = true, Label = "💻 Working at a desk" },
	counter = { Pose = "counter", Label = "🧾 Serving customers" },
	cashier = { Pose = "cashier", Label = "🧾 At the register" },
	cook = { Pose = "cook", Props = { "Pan" }, Label = "🍳 Cooking" },
	bake = { Pose = "knead", Label = "🥐 Baking" },
	brew = { Pose = "brew", Props = { "Cup" }, Label = "☕ Making coffee" },
	serve = { Pose = "carry", Props = { "Tray" }, Label = "🍽️ Serving tables" },
	teach = { Pose = "teach", Props = { "Chalk" }, Label = "👩‍🏫 Teaching" },
	doctor = { Pose = "clipboard", Props = { "Clipboard" }, Label = "🩺 Checking on patients" },
	nurse = { Pose = "clipboard", Props = { "Clipboard" }, Label = "💉 Caring for patients" },
	guard = { Pose = "guard", Label = "👮 On duty" },
	machine = { Pose = "machine", Props = { "Wrench" }, Label = "🏭 Running a machine" },
	carrybox = { Pose = "carry", Props = { "Box" }, Label = "📦 Moving boxes" },
	fixcar = { Pose = "crouchwork", Props = { "Wrench" }, Label = "🔧 Fixing a car" },
	sweep = { Pose = "sweep", Props = { "Broom" }, Label = "🧹 Sweeping" },
	garden = { Pose = "kneelwork", Props = { "Trowel" }, Label = "🌱 Gardening" },
	shelve = { Pose = "shelve", Props = { "Box" }, Label = "📚 Stocking shelves" },
	music = { Pose = "guitar", Props = { "Guitar" }, Label = "🎸 Playing music" },
	coach = { Pose = "cheer", Props = { "Clipboard", "Whistle" }, Label = "📣 Coaching" },
	present = { Pose = "present", Label = "🏛️ Leading a meeting" },
	sort = { Pose = "shelve", Props = { "Letter" }, Label = "✉️ Sorting mail" },
	babysit = { Pose = "counter", Label = "🧸 Looking after little ones" },
	guide = { Pose = "present", Label = "🖼️ Giving a tour" },
	-- errands and rounds (see Errands)
	pay = { Pose = "pay", Props = { "Card" }, Label = "💳 Paying" },
	checkout = { Pose = "pay", Props = { "Card" }, Label = "🛒 At the checkout" },
	deliver = { Pose = "deliver", Props = { "MailBag", "Letter" }, Label = "📬 Delivering the mail" },
	water = { Pose = "water", Props = { "WateringCan" }, Label = "🚿 Watering the plants" },
	rake = { Pose = "rake", Props = { "Rake" }, Label = "🍂 Raking leaves" },
	mop = { Pose = "mop", Props = { "Mop" }, Label = "🧽 Mopping the floor" },
	patrol = { Pose = "patrol", Props = { "Radio" }, Label = "👮 On patrol" },
	unpack = { Pose = "unpack", Props = { "Bag" }, Label = "🛍️ Putting the shopping away" },
	-- gym
	run = { Pose = "run", Label = "🏃 Running on the treadmill" },
	lift = { Pose = "curl", Props = { "Dumbbells" }, Label = "💪 Lifting weights" },
	squat = { Pose = "squat", Props = { "Barbell" }, Label = "🏋️ Squatting" },
	punch = { Pose = "punch", Label = "🥊 Hitting the bag" },
	yoga = { Pose = "yoga", Label = "🧘 Doing yoga" },
	stretch = { Pose = "stretch", Label = "🤸 Stretching" },
	-- everyday life
	eat = { Pose = "eat", Seated = true, Props = { "Fork" }, Label = "🍝 Eating" },
	coffee = { Pose = "drink", Seated = true, Props = { "Cup" }, Label = "☕ Having a coffee" },
	read = { Pose = "read", Seated = true, Props = { "Book" }, Label = "📖 Reading" },
	study = { Pose = "write", Seated = true, Props = { "Pencil" }, Label = "✏️ Studying" },
	watch = { Pose = "sit", Seated = true, Props = { "Popcorn" }, Label = "🎬 Watching" },
	tv = { Pose = "sit", Seated = true, Props = { "Remote" }, Label = "📺 Watching TV" },
	sleep = { Pose = "sleep", Lying = true, Label = "💤 Sleeping" },
	patient = { Pose = "sleep", Lying = true, Label = "🤒 Resting" },
	browse = { Pose = "browse", Label = "🛍️ Shopping" },
	phone = { Pose = "phone", Props = { "Phone" }, Label = "📱 On the phone" },
	chess = { Pose = "chess", Seated = true, Props = { "ChessPiece" }, Label = "♟️ Playing chess" },
	paint = { Pose = "paint", Props = { "Brush" }, Label = "🎨 Painting" },
	fish = { Pose = "fish", Props = { "Rod", "CaughtFish" }, Label = "🎣 Fishing" },
	birdwatch = { Pose = "binoculars", Props = { "Binoculars" }, Label = "🐦 Birdwatching" },
	knit = { Pose = "knit", Seated = true, Props = { "Knitting" }, Label = "🧶 Knitting" },
	guitar = { Pose = "guitar", Props = { "Guitar" }, Label = "🎸 Playing guitar" },
	dance = { Pose = "dance", Label = "💃 Dancing" },
	game = { Pose = "arcade", Label = "🕹️ Gaming" },
	cheer = { Pose = "cheer", Label = "📣 Cheering" },
	sit = { Pose = "sit", Seated = true, Label = "🪑 Relaxing" },
	chat = { Pose = "talk", Label = "💬 Chatting" },
	wait = { Pose = "idle", Label = "⏳ Waiting" },
	-- kids
	swing = { Pose = "swingsit", Seated = true, Swing = true, Label = "🛝 On the swings" },
	play = { Pose = "cheer", Label = "🛝 Playing" },
	hoops = { Pose = "shoot", Props = { "Basketball" }, Label = "🏀 Shooting hoops" },
	soccer = { Pose = "none", Label = "⚽ Playing soccer" },
	crawl = { Pose = "crawl", Label = "🧸 Playing" },
	nap = { Pose = "sleep", Lying = true, Label = "🍼 Napping" },
	-- reactions (short, set by CitizenService.React and friends)
	listen = { Pose = "listen", Label = "👂 Listening" },
	wave = { Pose = "wave", Label = "👋 Waving" },
	point = { Pose = "point", Label = "👉 Pointing the way" },
	boo = { Pose = "boo", Label = "👎 Booing" },
	scared = { Pose = "scared", Label = "😱 Scared" },
	-- street crime
	cuffed = { Pose = "cuffed", Props = { "Cuffs" }, Label = "🚓 Under arrest" },
	handsup = { Pose = "handsup", Label = "🙌 Giving up" },
	spray = { Pose = "spray", Props = { "SprayCan" }, Label = "🎨 Spraying graffiti" },
	jailed = { Pose = "jailed", Label = "🔒 In jail" },
	getaway = { Pose = "none", Props = { "Loot" }, Label = "💰 Running away" },
	ko = { Pose = "ko", Lying = true, Label = "💫 Knocked out" },
	carry = { Pose = "carry", Label = "👶 Carrying the baby" },
}

-- Checkouts (a customer and a clerk doing a sale together): how long each kind
-- takes, in seconds. The server starts them, every client animates them.
Actions.CheckoutTime = { shop = 9, food = 8 }

function Actions.Get(name)
	return Actions.List[name]
end

-- How far the body sits below standing height when seated / lying (in studs, before scaling)
Actions.SEAT_DROP = 1.1
Actions.LIE_DROP = 1.6

return Actions
