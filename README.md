## JMTradingHouseSnapshot

Addon for elder scroll online that makes a snapshot of your trading houses.
Other addons can request a new addon or register on events so they are notices when a new snapshot is created.

## Snapshot structure

```lua
snapshot =
{
    -- Holds the items grouped per guild
    tradingHouseItemList =
    {
        -- First guild
        1 =
        {
            -- First item
            {
                itemId = '',
                itemLink = '',
                sellerName = '',
                quality = '',
                stackCount = '',
                price = '',
                pricePerPiece = '',
                expiry = '',
            },
            -- Next item etc
            {
                -- ..
            }
        },

        -- Next guild etc
        2 = {
            -- ..
        }
    },

    -- Will list the guilds with their information
    guildList =
    {
        -- First guild
        1 =
        {
            id = '',
            name = '',
            alianceId = '',
        }
    },

    -- The creation timestamp of when the snapshot was finished building
    creationTimestamp = nil,
}
```

## API

### createSnapshot

```lua
JMTradingHouseSnapshot.createSnapshot()
```

Allows you to create a new snapshot.
The snapshot will not be returned because it will take a while.

### getSnapshot

```lua
local snapshot = JMTradingHouseSnapshot.getSnapshot()
```

Will return the latest successful snapshot or `false` if no snapshot was ever made.

### abort

```lua
JMTradingHouseSnapshot.abort()
```

Will abort the snapshot if running.

### registerForEvent

```lua
JMTradingHouseSnapshot.registerForEvent(event, callback)
```

Allows you to listen to an event. See Events for list of possible event.
The callback function will be called when the events triggers.

### unregisterForEvent

```lua
JMTradingHouseSnapshot.unregisterForEvent(event, callback)
```

Stop listening to an event

## Events

All possible events are listen in `JMTradingHouseSnapshot.events`

### SCAN_STARTED

```lua
JMTradingHouseSnapshot.events.SCAN_STARTED
```

Will be triggered when the scanner is starting to create a snapshot

```lua
JMTradingHouseSnapshot.registerForEvent(JMTradingHouseSnapshot.events.SCAN_STARTED, function ()
    d('Scan started')
end)
```

### SCAN_SUCCEEDED

```lua
JMTradingHouseSnapshot.events.SCAN_SUCCEEDED
```

Will be triggered when the snapshot has finished successfully.
The function will have one argument with the snapshot.

```lua
JMTradingHouseSnapshot.registerForEvent(JMTradingHouseSnapshot.events.SCAN_SUCCEEDED, function (snapshot)
    d('Scan finished successfully')
    d(snapshot)
end)
```

### SCAN_FAILED

```lua
JMTradingHouseSnapshot.events.SCAN_FAILED
```

Will be triggered when the scanner got aborted

```lua
JMTradingHouseSnapshot.registerForEvent(JMTradingHouseSnapshot.events.SCAN_FAILED, function ()
    d('Scan failed')
end)
```

### SCAN_ALREADY_RUNNING

```lua
JMTradingHouseSnapshot.events.SCAN_ALREADY_RUNNING
```

Will be triggered when the scanner is already making a snapshot

```lua
JMTradingHouseSnapshot.registerForEvent(JMTradingHouseSnapshot.events.SCAN_ALREADY_RUNNING, function ()
    d('Scan already running')
end)
```

### ADDON_LOADED

```lua
JMTradingHouseSnapshot.events.ADDON_LOADED
```

Will be triggered when the addon is fully setup.
So you know that you can ask for a scan.

```lua
JMTradingHouseSnapshot.registerForEvent(JMTradingHouseSnapshot.events.ADDON_LOADED, function ()
    d('Addon is loaded')
end)
```

## Disclaimer

This Add-on is not created by, affiliated with or sponsored by ZeniMax Media Inc. or its affiliates. The Elder Scrolls® and related logos are registered trademarks or trademarks of ZeniMax Media Inc. in the United States and/or other countries. All rights reserved.
