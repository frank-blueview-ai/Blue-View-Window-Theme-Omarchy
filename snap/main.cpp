// Copyright (c) 2026 The Blue View Group Corporation. Author: Frank Perez <frank@blueview.ai>
// Licensed under the PolyForm Noncommercial License 1.0.0.
//
// Blue View OS window snapping for Hyprland, like Windows: drag a window by its
// title bar (or SUPER + drag) and let go with the pointer at a screen edge.
//
//   left / right edge   that half of the screen
//   top edge            maximized
//   bottom edge         bottom half
//   a corner            that quarter
//
// While the pointer waits at an edge, a clear glass preview shows where the
// window will land. Snapped windows float; dragging one away from its snap
// brings back the size it had before.
//
// SUPER + SHIFT + T (bound in bvos-windows.lua) tiles every window on the
// workspace; pressing it again puts floating windows back where they were.
// Dragging a tiled window keeps it in its tile while the glass preview marks
// the tile under the pointer; letting go there swaps the two windows.

#define WLR_USE_UNSTABLE

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/view/Window.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/state/ViewStateTracker.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/plugins/HookSystem.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/layout/space/Space.hpp>
#include <hyprland/src/layout/supplementary/DragController.hpp>
#include <hyprland/src/managers/eventLoop/EventLoopManager.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/managers/KeybindManager.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/config/values/types/BoolValue.hpp>
#include <hyprland/src/config/values/types/ColorValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/render/pass/RectPassElement.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include <algorithm>
#include <chrono>
#include <vector>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}


inline HANDLE PHANDLE = nullptr;

enum eZone : uint8_t {
    ZONE_NONE = 0,
    ZONE_LEFT,
    ZONE_RIGHT,
    ZONE_TOP,
    ZONE_BOTTOM,
    ZONE_TOP_LEFT,
    ZONE_TOP_RIGHT,
    ZONE_BOTTOM_LEFT,
    ZONE_BOTTOM_RIGHT,
    ZONE_TILE, // over another tiled window: swap
};

// A window's floating place before "tile all", to put it back.
struct SFloatingPlace {
    PHLWINDOWREF window;
    CBox         box;
    bool         maximized = false;
};

struct STiledWorkspace {
    PHLWORKSPACEREF             workspace;
    std::vector<SFloatingPlace> places;
};

struct SSnapped {
    PHLWINDOWREF window;
    Vector2D     restoreSize; // floating size before the snap
    CBox         box;         // where the snap put it
};

static struct {
    struct {
        SP<Config::Values::CBoolValue>  enabled;
        SP<Config::Values::CBoolValue>  swap;
        SP<Config::Values::CIntValue>   edge;
        SP<Config::Values::CIntValue>   corner;
        SP<Config::Values::CColorValue> previewColor;
    } config;

    // The drag in progress.
    bool                                  dragging = false;
    PHLWINDOWREF                          window;
    Vector2D                              dragStart;
    bool                                  restored = false;

    // The preview.
    eZone                                 zone = ZONE_NONE;
    PHLMONITORREF                         monitor;
    CBox                                  previewBox; // global, logical
    std::chrono::steady_clock::time_point previewSince;

    std::vector<SSnapped>                 snapped;

    // Dragging a tiled window: it stays in its tile until dropped.
    bool                                  tileDragging = false;
    PHLWINDOWREF                          tileDragWindow;
    PHLWINDOWREF                          swapWith;

    std::vector<STiledWorkspace>          tiled;
    CFunctionHook*                        dragBeginHook = nullptr;
} g_state;

static constexpr double FADE_MS = 140.0;

// ---- Geometry ----------------------------------------------------------------

static eZone zoneAt(const Vector2D& pos, PHLMONITOR monitor) {
    const CBox   mon    = monitor->logicalBox();
    const double EDGE   = std::max<int64_t>(1, g_state.config.edge->value());
    const double CORNER = std::max<int64_t>(EDGE, g_state.config.corner->value());

    const bool   left   = pos.x <= mon.x + EDGE;
    const bool   right  = pos.x >= mon.x + mon.w - 1 - EDGE;
    const bool   top    = pos.y <= mon.y + EDGE;
    const bool   bottom = pos.y >= mon.y + mon.h - 1 - EDGE;

    // Corners: at a side edge near the top or bottom, or at the top or bottom edge near a side.
    const bool nearLeft   = pos.x <= mon.x + CORNER;
    const bool nearRight  = pos.x >= mon.x + mon.w - 1 - CORNER;
    const bool nearTop    = pos.y <= mon.y + CORNER;
    const bool nearBottom = pos.y >= mon.y + mon.h - 1 - CORNER;

    if ((left && nearTop) || (top && nearLeft))
        return ZONE_TOP_LEFT;
    if ((right && nearTop) || (top && nearRight))
        return ZONE_TOP_RIGHT;
    if ((left && nearBottom) || (bottom && nearLeft))
        return ZONE_BOTTOM_LEFT;
    if ((right && nearBottom) || (bottom && nearRight))
        return ZONE_BOTTOM_RIGHT;
    if (left)
        return ZONE_LEFT;
    if (right)
        return ZONE_RIGHT;
    if (top)
        return ZONE_TOP;
    if (bottom)
        return ZONE_BOTTOM;
    return ZONE_NONE;
}

// The tiled work area of the monitor's active workspace: minus the bar and outer gaps.
static CBox workAreaFor(PHLMONITOR monitor) {
    const auto WS = monitor->m_activeSpecialWorkspace ? monitor->m_activeSpecialWorkspace : monitor->m_activeWorkspace;
    if (WS && WS->m_space)
        return WS->m_space->workArea(false);
    return monitor->logicalBoxMinusReserved();
}

// The cell a zone covers, with inner gaps where it meets the other half, like tiling.
static CBox cellFor(eZone zone, PHLMONITOR monitor) {
    const CBox  AREA = workAreaFor(monitor);

    static auto PGAPSIN = CConfigValue<Config::IComplexConfigValue>("general:gaps_in");
    const auto* GAPS    = sc<Config::CCssGapData*>(PGAPSIN.ptr());

    const bool  L = zone == ZONE_LEFT || zone == ZONE_TOP_LEFT || zone == ZONE_BOTTOM_LEFT;
    const bool  R = zone == ZONE_RIGHT || zone == ZONE_TOP_RIGHT || zone == ZONE_BOTTOM_RIGHT;
    const bool  T = zone == ZONE_TOP_LEFT || zone == ZONE_TOP_RIGHT;
    const bool  B = zone == ZONE_BOTTOM || zone == ZONE_BOTTOM_LEFT || zone == ZONE_BOTTOM_RIGHT;

    double      x = AREA.x, y = AREA.y, w = AREA.w, h = AREA.h;

    if (L || R) {
        w = AREA.w / 2.0;
        if (R)
            x += w;
    }
    if (T || B) {
        h = AREA.h / 2.0;
        if (B)
            y += h;
    }

    // Inner gaps on the edges that face the rest of the screen.
    double gl = (R ? GAPS->m_left : 0), gr = (L ? GAPS->m_right : 0);
    double gt = (B ? GAPS->m_top : 0), gb = (T ? GAPS->m_bottom : 0);

    return CBox{x + gl, y + gt, w - gl - gr, h - gt - gb}.round();
}

// ---- Preview -----------------------------------------------------------------

static void damagePreview() {
    if (g_state.zone != ZONE_NONE)
        g_pHyprRenderer->damageBox(g_state.previewBox.copy().expand(2));
}

// `tileBox` is the tile to highlight for ZONE_TILE.
static void setPreview(eZone zone, PHLMONITOR monitor, const CBox& tileBox = {}) {
    if (zone == g_state.zone && monitor == g_state.monitor.lock() && (zone != ZONE_TILE || tileBox == g_state.previewBox))
        return;

    damagePreview();
    g_state.zone    = zone;
    g_state.monitor = monitor;
    if (zone != ZONE_NONE) {
        // Maximized windows fill the screen below the bar, without the outer gaps.
        g_state.previewBox   = zone == ZONE_TILE ? tileBox : zone == ZONE_TOP ? monitor->logicalBoxMinusReserved() : cellFor(zone, monitor);
        g_state.previewSince = std::chrono::steady_clock::now();
    }
    damagePreview();
}

static void renderPreview() {
    const auto MONITOR = g_pHyprRenderer->m_renderData.pMonitor.lock();
    if (g_state.zone == ZONE_NONE || !MONITOR || MONITOR != g_state.monitor.lock())
        return;

    const double ELAPSED = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - g_state.previewSince).count();
    const double FADE    = std::clamp(ELAPSED / FADE_MS, 0.0, 1.0);
    const double EASED   = 1.0 - (1.0 - FADE) * (1.0 - FADE);

    static auto  PROUNDING = CConfigValue<Config::INTEGER>("decoration:rounding");

    CHyprColor   tint{sc<uint64_t>(g_state.config.previewColor->value())};
    const double SCALE = MONITOR->m_scale;

    // Grows a touch from its center as it fades in.
    CBox box = g_state.previewBox.copy();
    box.expand(-(1.0 - EASED) * 10.0);
    box.translate(-MONITOR->m_position).scale(SCALE).round();

    // Frosted glass: blur what's behind, then a faint tint on top.
    CRectPassElement::SRectData glass;
    glass.box   = box;
    glass.color = CHyprColor{tint.r, tint.g, tint.b, tint.a * EASED};
    glass.round = std::max<int64_t>(*PROUNDING, 8) * SCALE;
    glass.blur  = true;
    glass.blurA = EASED;
    g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(glass));

    // A hairline edge so the outline reads on any background.
    const double LINE = std::max(1.0, std::round(SCALE));
    const auto   EDGE = CHyprColor{1.0, 1.0, 1.0, 0.22 * EASED};
    for (const CBox& b : {CBox{box.x, box.y, box.w, LINE}, CBox{box.x, box.y + box.h - LINE, box.w, LINE}, CBox{box.x, box.y + LINE, LINE, box.h - 2 * LINE},
                          CBox{box.x + box.w - LINE, box.y + LINE, LINE, box.h - 2 * LINE}}) {
        CRectPassElement::SRectData line;
        line.box   = b;
        line.color = EDGE;
        g_pHyprRenderer->m_renderPass.add(makeUnique<CRectPassElement>(line));
    }

    if (FADE < 1.0)
        damagePreview();
}

// ---- Snapping ----------------------------------------------------------------

static SSnapped* findSnapped(PHLWINDOW window) {
    std::erase_if(g_state.snapped, [](const SSnapped& s) { return !s.window.lock(); });
    auto it = std::ranges::find_if(g_state.snapped, [&](const SSnapped& s) { return s.window.lock() == window; });
    return it == g_state.snapped.end() ? nullptr : &*it;
}

static void applySnap(PHLWINDOW window, eZone zone, PHLMONITOR monitor) {
    if (!validMapped(window) || !monitor)
        return;

    const auto TARGET = window->layoutTarget();
    if (!TARGET)
        return;

    if (zone == ZONE_TOP) {
        if (!Fullscreen::controller()->isFullscreen(window, Fullscreen::FSMODE_MAXIMIZED))
            Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_MAXIMIZED, std::nullopt);
        return;
    }

    if (Fullscreen::controller()->isFullscreen(window))
        Fullscreen::controller()->setFullscreenMode(window, Fullscreen::FSMODE_NONE, std::nullopt);

    // Remember the size to come back to, unless it's moving from one snap to another.
    const auto* PREVIOUS    = findSnapped(window);
    Vector2D    restoreSize = PREVIOUS ? PREVIOUS->restoreSize : TARGET->lastFloatingSize();
    if (!PREVIOUS && TARGET->floating())
        restoreSize = TARGET->position().size();

    if (!TARGET->floating())
        g_layoutManager->changeFloatingMode(TARGET);

    // The cell holds the whole window; the title bar and border sit inside it.
    const CBox  CELL     = cellFor(zone, monitor);
    const auto  RESERVED = window->getFullWindowReservedArea();
    CBox        box{CELL.pos() + RESERVED.topLeft, CELL.size() - RESERVED.topLeft - RESERVED.bottomRight};

    const auto  MINSIZE = TARGET->minSize().value_or(Vector2D{MIN_WINDOW_SIZE, MIN_WINDOW_SIZE});
    const auto  MAXSIZE = TARGET->maxSize().value_or(Math::VECTOR2D_MAX);
    box.w               = std::clamp(box.w, MINSIZE.x, std::max(MINSIZE.x, MAXSIZE.x));
    box.h               = std::clamp(box.h, MINSIZE.y, std::max(MINSIZE.y, MAXSIZE.y));

    TARGET->rememberFloatingSize(restoreSize);
    g_layoutManager->setTargetGeom(box, TARGET);

    if (auto* s = findSnapped(window)) {
        s->box = box;
    } else {
        g_state.snapped.push_back({window, restoreSize, box});
    }
}

// Dragging a snapped window off its snap brings back its earlier size, keeping
// the pointer at the same spot across the title bar.
static void restoreOnDragAway(PHLWINDOW window, const Vector2D& pointer) {
    auto* s = findSnapped(window);
    if (!s)
        return;

    const auto TARGET  = window->layoutTarget();
    const auto CURRENT = TARGET->position();
    const auto SIZE    = s->restoreSize;
    std::erase_if(g_state.snapped, [&](const SSnapped& x) { return x.window.lock() == window; });

    if (SIZE.x < 1 || SIZE.y < 1 || !TARGET->floating())
        return;

    const double FRACTION = CURRENT.w > 0 ? std::clamp((pointer.x - CURRENT.x) / CURRENT.w, 0.0, 1.0) : 0.5;
    const double OFFSETY  = std::clamp(pointer.y - CURRENT.y, 0.0, SIZE.y);
    CBox         box{pointer.x - SIZE.x * FRACTION, pointer.y - OFFSETY, SIZE.x, SIZE.y};

    TARGET->setPositionGlobal(box.round());
    TARGET->warpPositionSize();
    // Re-anchor the drag on the new size so the window follows the pointer from here.
    g_layoutManager->dragController()->updateDragWindow();
}

// ---- Tile all ----------------------------------------------------------------

static PHLWORKSPACE activeWorkspace() {
    const auto MONITOR = Desktop::focusState()->monitor();
    if (!MONITOR)
        return nullptr;
    return MONITOR->m_activeSpecialWorkspace ? MONITOR->m_activeSpecialWorkspace : MONITOR->m_activeWorkspace;
}

static std::vector<PHLWINDOW> windowsOn(PHLWORKSPACE workspace) {
    std::vector<PHLWINDOW> out;
    for (const auto& w : Desktop::windowState()->windows()) {
        if (validMapped(w) && w->m_workspace == workspace && !w->isHidden() && !w->m_pinned && w->layoutTarget())
            out.push_back(w);
    }
    return out;
}

// Tiles every window on the active workspace. If they're already all tiled and
// this workspace was tiled by us, puts the windows that were floating back.
static void tileAll() {
    const auto WORKSPACE = activeWorkspace();
    if (!WORKSPACE)
        return;

    std::erase_if(g_state.tiled, [](const STiledWorkspace& t) { return !t.workspace.lock(); });
    auto       previous = std::ranges::find_if(g_state.tiled, [&](const STiledWorkspace& t) { return t.workspace.lock() == WORKSPACE; });

    const auto WINDOWS  = windowsOn(WORKSPACE);
    const bool ANYLOOSE = std::ranges::any_of(WINDOWS, [](const PHLWINDOW& w) { return w->m_isFloating || Fullscreen::controller()->isFullscreen(w); });

    if (!ANYLOOSE) {
        if (previous == g_state.tiled.end())
            return;

        // Restore: float them again, where they were.
        for (const auto& place : previous->places) {
            const auto W = place.window.lock();
            if (!validMapped(W) || W->m_workspace != WORKSPACE)
                continue;
            // A window that was maximized in its tile has no floating place; just maximize it again.
            if (!place.box.empty()) {
                const auto TARGET = W->layoutTarget();
                if (!TARGET->floating())
                    g_layoutManager->changeFloatingMode(TARGET);
                g_layoutManager->setTargetGeom(place.box, TARGET);
            }
            if (place.maximized)
                Fullscreen::controller()->setFullscreenMode(W, Fullscreen::FSMODE_MAXIMIZED, std::nullopt);
        }
        g_state.tiled.erase(previous);
        return;
    }

    STiledWorkspace state{WORKSPACE, {}};
    for (const auto& W : WINDOWS) {
        const bool MAXIMIZED = Fullscreen::controller()->isFullscreen(W);
        if (MAXIMIZED)
            Fullscreen::controller()->setFullscreenMode(W, Fullscreen::FSMODE_NONE, std::nullopt);

        const auto TARGET = W->layoutTarget();
        if (!TARGET->floating()) {
            if (MAXIMIZED)
                state.places.push_back({W, CBox{}, true});
            continue;
        }

        state.places.push_back({W, TARGET->position(), MAXIMIZED});
        std::erase_if(g_state.snapped, [&](const SSnapped& s) { return s.window.lock() == W; });
        g_layoutManager->changeFloatingMode(TARGET);
    }

    if (previous != g_state.tiled.end())
        *previous = std::move(state);
    else
        g_state.tiled.push_back(std::move(state));
}

// ---- Swap by drag ------------------------------------------------------------
//
// Hyprland lifts a tiled window out of the layout as soon as a drag begins, and
// the gap it leaves closes, so the tile can't be given back afterwards. Instead,
// a drag on a tiled window doesn't start Hyprland's drag at all: the window stays
// put, the preview follows the pointer, and the drop decides what happens.

static void endTileDrag() {
    if (!g_state.tileDragging)
        return;
    g_state.tileDragging = false;
    g_state.tileDragWindow.reset();
    g_state.swapWith.reset();
    setPreview(ZONE_NONE, nullptr);
    Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
}

static void hkDragBegin(Layout::Supplementary::CDragStateController* thisptr, SP<Layout::ITarget> target, eMouseBindMode mode, std::optional<Layout::eRectCorner> forcedEdge,
                        bool exclusiveDeviceGrab) {
    const auto WINDOW = target ? target->window() : nullptr;

    if (g_state.config.enabled->value() && g_state.config.swap->value() && mode == MBIND_MOVE && validMapped(WINDOW) && !target->floating() &&
        !Fullscreen::controller()->isFullscreen(WINDOW)) {
        g_state.tileDragging   = true;
        g_state.tileDragWindow = WINDOW;
        g_state.swapWith.reset();
        Pointer::Cursor::overrideController->setOverride("grabbing", Pointer::Cursor::CURSOR_OVERRIDE_SPECIAL_ACTION);
        return;
    }

    using FDragBegin = void (*)(Layout::Supplementary::CDragStateController*, SP<Layout::ITarget>, eMouseBindMode, std::optional<Layout::eRectCorner>, bool);
    ((FDragBegin)g_state.dragBeginHook->m_original)(thisptr, target, mode, forcedEdge, exclusiveDeviceGrab);
}

static void onTileDragMove(const Vector2D& pos) {
    const auto WINDOW  = g_state.tileDragWindow.lock();
    const auto MONITOR = State::monitorState()->query().vec(pos).run();
    if (!validMapped(WINDOW) || !MONITOR) {
        endTileDrag();
        return;
    }

    if (const auto ZONE = zoneAt(pos, MONITOR); ZONE != ZONE_NONE) {
        g_state.swapWith.reset();
        setPreview(ZONE, MONITOR);
        return;
    }

    const auto OTHER = Desktop::viewState()->hitTest().windowAt(pos, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS, WINDOW);
    if (validMapped(OTHER) && !OTHER->m_isFloating && OTHER->m_workspace == WINDOW->m_workspace && !Fullscreen::controller()->isFullscreen(OTHER)) {
        g_state.swapWith = OTHER;
        setPreview(ZONE_TILE, MONITOR, OTHER->getFullWindowBoundingBox());
    } else {
        g_state.swapWith.reset();
        setPreview(ZONE_NONE, nullptr);
    }
}

static void onTileDragDrop() {
    const auto WINDOW  = g_state.tileDragWindow.lock();
    const auto OTHER   = g_state.swapWith.lock();
    const auto ZONE    = g_state.zone;
    const auto MONITOR = g_state.monitor.lock();
    endTileDrag();

    if (!validMapped(WINDOW))
        return;

    if (ZONE == ZONE_TILE && validMapped(OTHER) && !OTHER->m_isFloating && !WINDOW->m_isFloating && OTHER->m_workspace == WINDOW->m_workspace) {
        g_layoutManager->switchTargets(WINDOW->layoutTarget(), OTHER->layoutTarget(), false);
    } else if (ZONE != ZONE_NONE && ZONE != ZONE_TILE) {
        applySnap(WINDOW, ZONE, MONITOR);
    }
}

// ---- Input -------------------------------------------------------------------

static PHLWINDOW draggedWindow() {
    const auto& DRAG = g_layoutManager->dragController();
    if (DRAG->mode() != MBIND_MOVE)
        return nullptr;
    const auto TARGET = DRAG->target();
    return TARGET ? TARGET->window() : nullptr;
}

static void onMouseMove(const Vector2D& pos) {
    if (g_state.tileDragging) {
        onTileDragMove(pos);
        return;
    }

    const auto WINDOW = g_state.config.enabled->value() ? draggedWindow() : nullptr;

    if (!WINDOW) {
        if (g_state.dragging) {
            g_state.dragging = false;
            setPreview(ZONE_NONE, nullptr);
        }
        return;
    }

    if (!g_state.dragging || g_state.window.lock() != WINDOW) {
        g_state.dragging  = true;
        g_state.window    = WINDOW;
        g_state.dragStart = pos;
        g_state.restored  = false;
    }

    if (!g_state.restored && pos.distance(g_state.dragStart) > 12) {
        g_state.restored = true;
        restoreOnDragAway(WINDOW, pos);
    }

    const auto MONITOR = State::monitorState()->query().vec(pos).run();
    setPreview(MONITOR ? zoneAt(pos, MONITOR) : ZONE_NONE, MONITOR);
}

static void onMouseButton(const IPointer::SButtonEvent& e) {
    if (e.state == WL_POINTER_BUTTON_STATE_PRESSED)
        return;

    if (g_state.tileDragging) {
        onTileDragDrop();
        return;
    }

    if (!g_state.dragging)
        return;

    const auto WINDOW  = g_state.window.lock();
    const auto ZONE    = g_state.zone;
    const auto MONITOR = g_state.monitor.lock();

    g_state.dragging = false;
    setPreview(ZONE_NONE, nullptr);

    if (!WINDOW || ZONE == ZONE_NONE)
        return;

    // Let Hyprland finish the drag first, then snap.
    g_pEventLoopManager->doLater([W = PHLWINDOWREF{WINDOW}, ZONE, M = PHLMONITORREF{MONITOR}] {
        if (g_layoutManager->dragController()->mode() != MBIND_INVALID)
            return;
        applySnap(W.lock(), ZONE, M.lock());
    });
}

// `hl.plugin.bvos_snap.version()`: also lets the Lua config tell the plugin is loaded.
static int luaVersion(lua_State* L) {
    lua_pushstring(L, "1.1");
    return 1;
}

// `hl.plugin.bvos_snap.tile_all()`: tile every window, or put floating windows back.
static int luaTileAll(lua_State* L) {
    if (g_state.config.enabled->value())
        tileAll();
    return 0;
}

#ifdef BVOS_SNAP_TEST
// Test build only: `hyprctl eval 'hl.plugin.bvos_snap.snap("left")'` snaps the
// focused window, and `...preview("left")` shows the preview, without a mouse.
static eZone zoneNamed(const std::string& name) {
    static const std::pair<const char*, eZone> NAMES[] = {{"left", ZONE_LEFT},          {"right", ZONE_RIGHT},          {"top", ZONE_TOP},
                                                          {"bottom", ZONE_BOTTOM},      {"top_left", ZONE_TOP_LEFT},    {"top_right", ZONE_TOP_RIGHT},
                                                          {"bottom_left", ZONE_BOTTOM_LEFT}, {"bottom_right", ZONE_BOTTOM_RIGHT}};
    for (const auto& [n, z] : NAMES)
        if (name == n)
            return z;
    return ZONE_NONE;
}

static int luaSnap(lua_State* L) {
    const auto WINDOW = Desktop::focusState()->window();
    if (WINDOW)
        applySnap(WINDOW, zoneNamed(luaL_checkstring(L, 1)), WINDOW->m_monitor.lock());
    return 0;
}

static int luaPreview(lua_State* L) {
    const auto MONITOR = Desktop::focusState()->monitor();
    setPreview(zoneNamed(luaL_checkstring(L, 1)), MONITOR);
    return 0;
}

// Simulates a drag of the i-th window of the active workspace to (x, y) and a drop there,
// through Hyprland's own drag start (so the hook runs).
static int luaDragTest(lua_State* L) {
    const auto WINDOWS = windowsOn(activeWorkspace());
    const auto I       = (size_t)luaL_checkinteger(L, 1);
    const Vector2D TO{luaL_checknumber(L, 2), luaL_checknumber(L, 3)};
    if (I >= WINDOWS.size())
        return 0;
    g_layoutManager->beginDragTarget(WINDOWS[I]->layoutTarget(), MBIND_MOVE);
    const bool VIA_TILE_DRAG = g_state.tileDragging;
    Pointer::mgr()->warpTo(TO);
    onMouseMove(TO);
    const auto ZONE = g_state.zone;
    IPointer::SButtonEvent release;
    release.state = WL_POINTER_BUTTON_STATE_RELEASED;
    onMouseButton(release);
    if (!VIA_TILE_DRAG)
        CKeybindManager::changeMouseBindMode(MBIND_INVALID);
    lua_pushboolean(L, VIA_TILE_DRAG);
    lua_pushinteger(L, ZONE);
    return 2;
}

static int luaHookOk(lua_State* L) {
    lua_pushboolean(L, g_state.dragBeginHook != nullptr);
    return 1;
}

static int luaZoneAt(lua_State* L) {
    const Vector2D POS{luaL_checknumber(L, 1), luaL_checknumber(L, 2)};
    const auto     MONITOR = State::monitorState()->query().vec(POS).run();
    lua_pushinteger(L, MONITOR ? zoneAt(POS, MONITOR) : -1);
    return 1;
}
#endif

// ---- Plugin ------------------------------------------------------------------

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    const std::string HASH        = __hyprland_api_get_hash();
    const std::string CLIENT_HASH = __hyprland_api_get_client_hash();
    if (HASH != CLIENT_HASH) {
        HyprlandAPI::addNotification(PHANDLE, "[bvos-snap] Version mismatch: rebuild with bvos-hyprbars-build", CHyprColor{1.0, 0.2, 0.2, 1.0}, 5000);
        throw std::runtime_error("[bvos-snap] Version mismatch");
    }

    g_state.config.enabled      = makeShared<Config::Values::CBoolValue>("plugin:bvos_snap:enabled", "Snap windows dragged to a screen edge", true);
    g_state.config.swap         = makeShared<Config::Values::CBoolValue>("plugin:bvos_snap:swap", "Dragging a tiled window onto another swaps them", true);
    g_state.config.edge         = makeShared<Config::Values::CIntValue>("plugin:bvos_snap:edge", "Distance from a screen edge that snaps, in pixels", 6);
    g_state.config.corner       = makeShared<Config::Values::CIntValue>("plugin:bvos_snap:corner", "Distance along an edge that counts as a corner, in pixels", 120);
    g_state.config.previewColor = makeShared<Config::Values::CColorValue>("plugin:bvos_snap:preview_color", "Glass preview tint", 0x1438b6ff);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_state.config.enabled);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_state.config.swap);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_state.config.edge);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_state.config.corner);
    HyprlandAPI::addConfigValueV2(PHANDLE, g_state.config.previewColor);

    static auto MOVE   = Event::bus()->m_events.input.mouse.move.listen([](Vector2D pos, Event::SCallbackInfo&) { onMouseMove(pos); });
    static auto BUTTON = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent e, Event::SCallbackInfo&) { onMouseButton(e); });
    static auto RENDER = Event::bus()->m_events.render.stage.listen([](eRenderStage stage) {
        if (stage == RENDER_POST_WINDOWS)
            renderPreview();
    });

    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "version", luaVersion);
    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "tile_all", luaTileAll);
#ifdef BVOS_SNAP_TEST
    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "snap", luaSnap);
    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "preview", luaPreview);
    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "zone_at", luaZoneAt);
    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "drag_test", luaDragTest);
    HyprlandAPI::addLuaFunction(PHANDLE, "bvos_snap", "hook_ok", luaHookOk);
#endif

    // Swapping by drag starts before Hyprland would lift a tiled window out of the layout.
    for (const auto& match : HyprlandAPI::findFunctionsByName(PHANDLE, "dragBegin")) {
        if (match.demangled.find("CDragStateController::dragBegin") == std::string::npos)
            continue;
        g_state.dragBeginHook = HyprlandAPI::createFunctionHook(PHANDLE, match.address, (void*)&hkDragBegin);
        if (g_state.dragBeginHook && !g_state.dragBeginHook->hook())
            g_state.dragBeginHook = nullptr;
        break;
    }
    if (!g_state.dragBeginHook)
        HyprlandAPI::addNotification(PHANDLE, "[bvos-snap] Swapping windows by drag is unavailable on this Hyprland version", CHyprColor{1.0, 0.8, 0.2, 1.0}, 5000);

    HyprlandAPI::reloadConfig();

    return {"bvos-snap", "Blue View OS: snap windows to edges and corners, tile all, swap by drag", "The Blue View Group Corporation", "1.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    endTileDrag();
    setPreview(ZONE_NONE, nullptr);
    g_state.snapped.clear();
    g_state.tiled.clear();
    // Hyprland removes the plugin's function hooks itself when it unloads.
}
