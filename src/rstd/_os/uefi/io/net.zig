const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const unsupported = @import("__root__.zig").unsupported;

pub fn netListenIp(_: ?*anyopaque, _: *const Io.net.IpAddress, _: Io.net.IpAddress.ListenOptions) Io.net.IpAddress.ListenError!Io.net.Socket {
    unsupported(@src());
}

pub fn netAccept(_: ?*anyopaque, _: Io.net.Socket.Handle, _: Io.net.Server.AcceptOptions) Io.net.Server.AcceptError!Io.net.Socket {
    unsupported(@src());
}

pub fn netBindIp(_: ?*anyopaque, _: *const Io.net.IpAddress, _: Io.net.IpAddress.BindOptions) Io.net.IpAddress.BindError!Io.net.Socket {
    unsupported(@src());
}

pub fn netConnectIp(_: ?*anyopaque, _: *const Io.net.IpAddress, _: Io.net.IpAddress.ConnectOptions) Io.net.IpAddress.ConnectError!Io.net.Socket {
    unsupported(@src());
}

pub fn netListenUnix(_: ?*anyopaque, _: *const Io.net.UnixAddress, _: Io.net.UnixAddress.ListenOptions) Io.net.UnixAddress.ListenError!Io.net.Socket.Handle {
    unsupported(@src());
}

pub fn netConnectUnix(_: ?*anyopaque, _: *const Io.net.UnixAddress) Io.net.UnixAddress.ConnectError!Io.net.Socket.Handle {
    unsupported(@src());
}

pub fn netSocketCreatePair(_: ?*anyopaque, _: Io.net.Socket.CreatePairOptions) Io.net.Socket.CreatePairError![2]Io.net.Socket {
    unsupported(@src());
}

pub fn netSend(_: ?*anyopaque, _: Io.net.Socket.Handle, _: []Io.net.OutgoingMessage, _: Io.net.SendFlags) struct { ?Io.net.Socket.SendError, usize } {
    unsupported(@src());
}

pub fn netWrite(_: ?*anyopaque, _: Io.net.Socket.Handle, _: []const u8, _: []const []const u8, _: usize) Io.net.Stream.Writer.Error!usize {
    unsupported(@src());
}

pub fn netWriteFile(_: ?*anyopaque, _: Io.net.Socket.Handle, _: []const u8, _: *Io.File.Reader, _: Io.Limit) Io.net.Stream.Writer.WriteFileError!usize {
    unsupported(@src());
}

pub fn netClose(_: ?*anyopaque, _: []const Io.net.Socket.Handle) void {
    unsupported(@src());
}

pub fn netShutdown(_: ?*anyopaque, _: Io.net.Socket.Handle, _: Io.net.ShutdownHow) Io.net.ShutdownError!void {
    unsupported(@src());
}

pub fn netInterfaceNameResolve(_: ?*anyopaque, _: *const Io.net.Interface.Name) Io.net.Interface.Name.ResolveError!Io.net.Interface {
    unsupported(@src());
}

pub fn netInterfaceName(_: ?*anyopaque, _: Io.net.Interface) Io.net.Interface.NameError!Io.net.Interface.Name {
    unsupported(@src());
}

pub fn netLookup(_: ?*anyopaque, _: Io.net.HostName, _: *Io.Queue(Io.net.HostName.LookupResult), _: Io.net.HostName.LookupOptions) Io.net.HostName.LookupError!void {
    unsupported(@src());
}
