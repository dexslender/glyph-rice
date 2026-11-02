pragma Singleton

import Quickshell
import Niri as NiriPlugin
import QtQml

Singleton {
    id: root

    NiriPlugin.Niri {
        id: client

        Component.onCompleted: connect()
    }

    property alias workspaces: client.workspaces
    property alias windows: client.windows
    property alias focusedWindow: client.focusedWindow

    function focusWorkspace(index) {
        return client.focusWorkspace(index);
    }

    function focusWorkspaceById(id) {
        return client.focusWorkspaceById(id);
    }

    function focusWorkspaceByName(name) {
        return client.focusWorkspaceByName(name);
    }

    function focusWindow(id) {
        return client.focusWindow(id);
    }

    function closeWindow(id) {
        return client.closeWindow(id);
    }

    function closeWindowOrFocused(id) {
        return client.closeWindowOrFocused(id);
    }

    function toggleOverview() {
        return client.toggleOverview();
    }

    function sendRawAction(action) {
        return client.sendRawAction(action);
    }
}
