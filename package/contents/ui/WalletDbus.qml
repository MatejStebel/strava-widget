import QtQuick
import org.kde.plasma.workspace.dbus as DBus

QtObject {
    id: backend

    // Separate credentials from other widgets; never store passwords in configuration.
    readonly property string folder: "Strava Plasma Widget"
    readonly property string applicationId: "cz.saruman.strava"
    property var operationQueue: Promise.resolve()
    // Keep replies alive until their finished signal, including during QML GC.
    property var pendingReplies: []

    function call(member, signature, args) {
        return new Promise(function(resolve, reject) {
            // The single-argument API is available in Debian 13's Plasma 6.3.
            var reply = DBus.SessionBus.asyncCall({
                service: "org.kde.kwalletd6",
                path: "/modules/kwalletd6",
                iface: "org.kde.KWallet",
                member: member,
                signature: signature,
                arguments: args
            })
            pendingReplies.push(reply)
            var completed = false
            function finish() {
                if (completed) { return }
                completed = true
                var valid = reply.isValid && !reply.isError
                // Copy scalar values before destroying the reply object.
                var value = valid ? reply.value : undefined
                if (value !== null && typeof value === "object" && value.value !== undefined) {
                    value = value.value
                }
                reply.finished.disconnect(finish)
                pendingReplies.splice(pendingReplies.indexOf(reply), 1)
                reply.destroy()
                if (valid) {
                    resolve(value)
                } else {
                    // Do not expose daemon messages which might contain arguments.
                    reject(new Error("KWallet request failed: " + member))
                }
            }
            reply.finished.connect(finish)
            if (reply.isFinished) { finish() }
        })
    }

    function withWallet(operation) {
        var handle = -1
        return call("networkWallet", "()", []).then(function(name) {
            if (!name) {
                throw new Error("No network wallet is configured")
            }
            // Explicit signatures marshal the window ID as int64, not a JS double.
            return call("open", "(sxs)", [name, 0, applicationId])
        }).then(function(result) {
            if (result < 0) {
                throw new Error("KWallet was not opened")
            }
            handle = result
            return operation(handle)
        }).then(function(value) {
            return closeHandle(handle).then(function() { return value })
        }, function(error) {
            return closeHandle(handle).then(function() { throw error })
        })
    }

    function closeHandle(handle) {
        if (handle < 0) {
            return Promise.resolve()
        }
        // Release only our handle; never force-close another application's wallet.
        return call("close", "(ibs)", [handle, false, applicationId]).catch(function() {})
    }

    function enqueue(operation, callback) {
        // A logout deletion must run after any password save already in progress.
        operationQueue = operationQueue.then(function() {
            return withWallet(operation)
        }).then(function(value) {
            callback("", value)
        }, function(error) {
            callback(error.message, "")
        }).catch(function() {
            // A caller throwing must not prevent subsequent wallet operations.
            console.error("Credential operation callback failed")
        })
    }

    function loadPassword(key, callback) {
        enqueue(function(handle) {
            return call("hasEntry", "(isss)", [handle, folder, key, applicationId])
                .then(function(exists) {
                    return exists
                        ? call("readPassword", "(isss)", [handle, folder, key, applicationId])
                        : ""
                })
        }, callback)
    }

    function savePassword(key, password, callback) {
        enqueue(function(handle) {
            return call("hasFolder", "(iss)", [handle, folder, applicationId])
                .then(function(exists) {
                    return exists || call("createFolder", "(iss)", [handle, folder, applicationId])
                }).then(function(created) {
                    if (!created) {
                        throw new Error("Could not create the KWallet folder")
                    }
                    return call("writePassword", "(issss)", [handle, folder, key, password, applicationId])
                }).then(function(result) {
                    if (result !== 0) {
                        throw new Error("Could not save the password to KWallet")
                    }
                })
        }, callback)
    }

    function deletePassword(key, callback) {
        enqueue(function(handle) {
            return call("hasEntry", "(isss)", [handle, folder, key, applicationId])
                .then(function(exists) {
                    return exists
                        ? call("removeEntry", "(isss)", [handle, folder, key, applicationId])
                        : 0
                }).then(function(result) {
                    if (result !== 0) {
                        throw new Error("Could not remove the password from KWallet")
                    }
                })
        }, callback)
    }
}
