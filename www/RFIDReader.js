var exec = require('cordova/exec');
var PLUGIN_NAME = 'RFIDReader';
var ReaderCordovaPlugin ={
    pair = function (arg0, success, error) {
        exec(success, error, 'RFIDReader', 'pair', [arg0]);
    },
    read = function (arg0, success, error) {
        exec(success, error, 'RFIDReader', 'read', [arg0]);
    },
    write = function (arg0, success, error) {
        exec(success, error, 'RFIDReader', 'write', [arg0]);
    },
    reconnect = function (arg0, success, error) {
        exec(success, error, 'RFIDReader', 'reconnect', [arg0]);
    }
    disconnect = function (arg0, success, error) {
        exec(success, error, 'RFIDReader', 'disconnect', [arg0]);
    }

};

module.exports = ReaderCordovaPlugin;
