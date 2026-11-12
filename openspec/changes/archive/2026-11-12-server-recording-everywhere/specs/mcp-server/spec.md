# Spec Delta

## ADDED Requirements

### Requirement: Server recordings through the tools
With a paired Fernsy Server, `schedule_recording` SHALL take `where` (`device` or `server`) and
order the show on the server for `server`, with the rules of ordering in the app, and its result
SHALL say where the show was scheduled. `list_recordings` SHALL also list the server's orders with
their state, marked as the server's. `cancel_recording` SHALL remove a server order that has not
started and SHALL leave running and finished ones alone.

#### Scenario: Ordering on the server
- **WHEN** the assistant calls `schedule_recording` with `where: server` for tonight's show
- **THEN** the show is listed under the server's orders in Recordings on every device and the result says it was scheduled on the server

#### Scenario: Without where on the Mac
- **WHEN** the assistant calls `schedule_recording` without `where` on the Mac
- **THEN** the Mac schedules the show itself, as before, and the result says it was scheduled on the device

#### Scenario: No server paired
- **WHEN** the assistant calls `schedule_recording` with `where: server` and no server is paired
- **THEN** the tool returns an error that names Settings as the place to pair one, and nothing is scheduled

#### Scenario: Listing
- **WHEN** the server has an order from the iPad and the assistant calls `list_recordings` on the Mac
- **THEN** the result lists the Mac's recordings and that order, the order marked as the server's with its state

#### Scenario: Cancelling a server order
- **WHEN** the assistant calls `cancel_recording` for a server order that is scheduled
- **THEN** the order is removed on the server and every device stops listing it

#### Scenario: Server order that records
- **WHEN** the assistant calls `cancel_recording` for a server order that is recording
- **THEN** the tool returns an error and the server keeps recording
