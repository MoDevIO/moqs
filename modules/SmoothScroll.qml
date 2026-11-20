import QtQuick

// Scrolling like in a browser, for a Flickable or ListView (put it inside, naming the view).
// Everything runs once per frame: a wheel notch sets a target the view eases towards
// (notches in quick succession add up), a touchpad moves the view with the fingers, and once
// they lift it coasts on and slows down. Positions snap to whole device pixels, so text stays
// sharp at fractional scales. At the end of the content, the view around it (if any)
// scrolls on instead.
WheelHandler {
    id: root

    required property Flickable flickable
    // Pixels per wheel notch.
    property real step: 100
    // Seconds the eases take to get most of the way (about 63%) there: a wheel notch, and
    // following the fingers, which smooths out touchpad reports arriving unevenly
    // between frames.
    property real wheelEase: 0.055
    property real touchEase: 0.012
    // Seconds coasting takes to lose most of its speed.
    property real coast: 0.33

    // The view being scrolled, which may be an outer one, and where it is and is headed.
    property Flickable view
    property real pos
    property real dest
    property real ease
    // Coasting speed in px/s; 0 while not coasting.
    property real velocity
    // What was last written to contentY, to notice when something else moves the view.
    property real written
    // Recent touchpad moves, for the coasting speed: [{ t, d }], t in ms.
    property var samples: []
    // Whether the touchpad reports when fingers lift. Without that, a pause ends the scroll.
    property bool phases

    function bounds(f: Flickable): var {
        const min = f.originY - f.topMargin;
        return { min, max: Math.max(min, f.originY + f.contentHeight + f.bottomMargin - f.height) };
    }

    // The nearest view around this one.
    function outer(f: Item): Flickable {
        for (let p = f.parent; p; p = p.parent)
            if (p.flick !== undefined && p.contentY !== undefined)
                return p;
        return null;
    }

    // Whether f can scroll by d (positive: towards the end) from where it's headed.
    function canScroll(f: Flickable, d: real): bool {
        if (!f.interactive || f.contentHeight + f.topMargin + f.bottomMargin <= f.height)
            return false;
        const b = bounds(f);
        const at = f === view && frames.running ? dest : f.contentY;
        return d > 0 ? at < b.max - 0.5 : at > b.min + 0.5;
    }

    // Starts driving f, from where it is now unless it's already being driven.
    function take(f: Flickable): void {
        if (f === view && frames.running && Math.abs(f.contentY - written) < 1)
            return;
        view = f;
        pos = f.contentY;
        dest = pos;
        written = pos;
        velocity = 0;
        f.cancelFlick();
        frames.start();
    }

    // The view this scroll goes to: this one, or the nearest outer one that can still move.
    function pick(d: real): Flickable {
        for (let f = flickable; f; f = outer(f))
            if (canScroll(f, d))
                return f;
        return null;
    }

    // Scrolls by d pixels (positive: towards the end), eased over ease seconds.
    function scrollBy(d: real, e: real): void {
        const f = pick(d);
        if (!f)
            return;
        take(f);
        const b = bounds(f);
        velocity = 0;
        ease = e;
        dest = Math.max(b.min, Math.min(b.max, dest + d));
    }

    function notch(notches: real): void {
        scrollBy(-notches * step, wheelEase);
    }

    // A touchpad move of d pixels (positive: fingers towards the top, content up).
    function touch(d: real): void {
        const now = Date.now();
        samples = [...samples.filter(s => now - s.t < 100), { t: now, d }];
        scrollBy(d, touchEase);
        if (!phases)
            lift.restart();
    }

    // Fingers lifted: coast on at the speed of the last moves.
    function release(): void {
        lift.stop();
        const now = Date.now();
        const recent = samples.filter(s => now - s.t < 100);
        samples = [];
        if (!view || recent.length < 2)
            return;
        const span = Math.max(16, now - recent[0].t);
        const speed = recent.reduce((a, s) => a + s.d, 0) / span * 1000;
        if (Math.abs(speed) < 100)
            return;
        // Coast from where the fingers took it.
        dest = Math.max(bounds(view).min, Math.min(bounds(view).max, dest));
        velocity = speed;
        frames.start();
    }

    function stop(): void {
        frames.stop();
        velocity = 0;
        samples = [];
    }

    target: null
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    onWheel: event => {
        if (event.phase !== Qt.NoScrollPhase)
            phases = true;
        const touchpad = event.pixelDelta.y !== 0 || event.phase !== Qt.NoScrollPhase;
        if (!touchpad) {
            if (event.angleDelta.y !== 0)
                notch(event.angleDelta.y / 120);
        } else if (event.phase === Qt.ScrollEnd) {
            release();
        } else if (event.pixelDelta.y !== 0) {
            touch(-event.pixelDelta.y);
        }
    }

    // A handler takes no children, so these are properties.
    readonly property FrameAnimation frames: FrameAnimation {
        onTriggered: {
            const f = root.view;
            // Gone, or moved by something else (a drag, keys): let go.
            if (!f || Math.abs(f.contentY - root.written) >= 1) {
                root.stop();
                return;
            }
            const dt = Math.min(frameTime, 0.05);
            const b = root.bounds(f);
            if (root.velocity !== 0) {
                root.dest += root.velocity * dt;
                root.velocity *= Math.exp(-dt / root.coast);
                if (Math.abs(root.velocity) < 20 || root.dest <= b.min || root.dest >= b.max)
                    root.velocity = 0;
                root.dest = Math.max(b.min, Math.min(b.max, root.dest));
                root.pos = root.dest;
            } else {
                root.pos += (root.dest - root.pos) * (1 - Math.exp(-dt / root.ease));
            }
            const dpr = Screen.devicePixelRatio || 1;
            const settled = root.velocity === 0 && Math.abs(root.dest - root.pos) < 0.5 / dpr;
            if (settled)
                root.pos = root.dest;
            root.written = Math.round(root.pos * dpr) / dpr;
            f.contentY = root.written;
            if (settled)
                root.stop();
        }
    }

    // Without lift reports from the touchpad, a short pause counts as lifting.
    readonly property Timer lift: Timer {
        interval: 60
        onTriggered: root.release()
    }
}
