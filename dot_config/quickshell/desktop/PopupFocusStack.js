.pragma library

// Only the most recently mapped popup may own the seat grab. Keep older
// popups in order so closing the top one returns input to the next one.
var owners = [];
var blocked = false;

function sync() {
    const top = !blocked && owners.length ? owners[owners.length - 1] : null;
    for (const owner of owners) owner.ownsInput = owner === top;
}

function show(owner) {
    if (owners.indexOf(owner) !== -1) return;
    owners.push(owner);
    sync();
}

function hide(owner) {
    owner.ownsInput = false;
    owners = owners.filter(candidate => candidate !== owner);
    sync();
}

function setBlocked(value) {
    blocked = value;
    sync();
}
