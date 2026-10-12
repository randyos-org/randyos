//! Authenticode signing of PE/COFF images (UEFI Secure Boot), per Microsoft's
//! "Windows Authenticode Portable Executable Signature Format": a PKCS#7
//! SignedData over the image hash, RSA PKCS#1 v1.5 with SHA-256, appended as
//! a WIN_CERTIFICATE in the certificate table.

const std = @import("std");
const rstd = @import("rstd");
const bytes = rstd.bytes;
const der = rstd.crypto.der;
const Allocator = std.mem.Allocator;
const Sha256 = std.crypto.hash.sha2.Sha256;
const Tag = der.Tag;

pub const PrivateKey = rstd.crypto.rsa.PrivateKey;
pub const Cert = rstd.crypto.x509.Cert;

const oid_spc_indirect_data = der.oid("\x2b\x06\x01\x04\x01\x82\x37\x02\x01\x04");
const oid_spc_sp_opus_info = der.oid("\x2b\x06\x01\x04\x01\x82\x37\x02\x01\x0c");
const oid_spc_pe_image_data = der.oid("\x2b\x06\x01\x04\x01\x82\x37\x02\x01\x0f");

const Pe = struct {
    checksum: usize,
    cert_dir: usize,
    headers_end: usize,
    /// (offset, size) of section raw data in file order.
    sections: []const [2]usize,

    fn parse(arena: Allocator, img: []const u8) !Pe {
        if (img.len < 0x40 or !std.mem.eql(u8, img[0..2], "MZ")) return error.NotPe;
        const pe = bytes.readIntLE(u32, img[0x3C..]);
        if (img.len < pe + 24 or !std.mem.eql(u8, img[pe..][0..4], "PE\x00\x00")) return error.NotPe;
        const coff = pe + 4;
        const nsec = bytes.readIntLE(u16, img[coff + 2 ..]);
        const opt_size = bytes.readIntLE(u16, img[coff + 16 ..]);
        const opt = coff + 20;
        const pe32plus = switch (bytes.readIntLE(u16, img[opt..])) {
            0x20B => true,
            0x10B => false,
            else => return error.NotPe,
        };
        const ndirs = bytes.readIntLE(u32, img[opt + @as(usize, if (pe32plus) 108 else 92) ..]);
        if (ndirs < 5) return error.NoCertDirectory;
        var secs: std.ArrayList([2]usize) = .empty;
        const table = opt + opt_size;
        if (img.len < table + 40 * @as(usize, nsec)) return error.NotPe;
        for (0..nsec) |i| {
            const s = img[table + 40 * i ..];
            const size = bytes.readIntLE(u32, s[16..]);
            if (size > 0) try secs.append(arena, .{ bytes.readIntLE(u32, s[20..]), size });
        }
        std.mem.sort([2]usize, secs.items, {}, struct {
            fn lt(_: void, a: [2]usize, b: [2]usize) bool {
                return a[0] < b[0];
            }
        }.lt);
        return .{
            .checksum = opt + 64,
            .cert_dir = opt + @as(usize, if (pe32plus) 112 else 96) + 4 * 8,
            .headers_end = bytes.readIntLE(u32, img[opt + 60 ..]),
            .sections = secs.items,
        };
    }

    /// Authenticode digest: everything except the checksum, the
    /// certificate table entry and the certificate table itself.
    fn digest(p: Pe, img: []const u8) ![32]u8 {
        var h: Sha256 = .init(.{});
        h.update(img[0..p.checksum]);
        h.update(img[p.checksum + 4 .. p.cert_dir]);
        h.update(img[p.cert_dir + 8 .. p.headers_end]);
        var hashed = p.headers_end;
        for (p.sections) |s| {
            if (s[0] + s[1] > img.len) return error.NotPe;
            h.update(img[s[0]..][0..s[1]]);
            hashed += s[1];
        }
        const cert_size = bytes.readIntLE(u32, img[p.cert_dir + 4 ..]);
        const cert_at = if (cert_size == 0) img.len else bytes.readIntLE(u32, img[p.cert_dir..]);
        if (cert_at > hashed) h.update(img[hashed..cert_at]);
        return h.finalResult();
    }
};

/// Returns `img` signed with `key`, whose certificate is `cert`.
pub fn sign(arena: Allocator, img: []const u8, key: PrivateKey, cert: Cert) ![]u8 {
    if (!std.mem.eql(u8, key.n, cert.rsa_n)) return error.KeyCertMismatch;
    const pe = try Pe.parse(arena, img);
    if (bytes.readIntLE(u32, img[pe.cert_dir + 4 ..]) != 0) return error.AlreadySigned;

    // The certificate table starts 8-aligned; the padding is hashed.
    const padded = try arena.alloc(u8, std.mem.alignForward(usize, img.len, 8));
    @memcpy(padded[0..img.len], img);
    @memset(padded[img.len..], 0);
    const image_digest = try pe.digest(padded);

    const sha256_alg = try der.encode(arena, Tag.seq, &.{ der.Oid.sha256, &der.null_value });
    const obsolete = std.unicode.utf8ToUtf16LeStringLiteral("<<<Obsolete>>>");
    var obsolete_be: [obsolete.len * 2]u8 = undefined;
    for (obsolete, 0..) |c, i| bytes.writeIntBE(u16, obsolete_be[2 * i ..], c);
    const spc_link = try der.encode(arena, 0xA2, &.{try der.encode(arena, 0x80, &.{&obsolete_be})});
    const pe_image_data = try der.encode(arena, Tag.seq, &.{ &.{ Tag.bits, 1, 0 }, try der.encode(arena, Tag.context(0), &.{spc_link}) });
    const spc = try der.encode(arena, Tag.seq, &.{
        try der.encode(arena, Tag.seq, &.{ oid_spc_pe_image_data, pe_image_data }),
        try der.encode(arena, Tag.seq, &.{ sha256_alg, try der.encode(arena, Tag.octets, &.{&image_digest}) }),
    });

    // messageDigest covers the SpcIndirectDataContent's contents, not its header.
    var attrs = [_][]const u8{
        try der.encode(arena, Tag.seq, &.{ der.Oid.pkcs9_content_type, try der.encode(arena, Tag.set, &.{oid_spc_indirect_data}) }),
        try der.encode(arena, Tag.seq, &.{ oid_spc_sp_opus_info, try der.encode(arena, Tag.set, &.{&.{ Tag.seq, 0 }}) }),
        try der.encode(arena, Tag.seq, &.{ der.Oid.pkcs9_message_digest, try der.encode(arena, Tag.set, &.{
            try der.encode(arena, Tag.octets, &.{&sha256Of((try der.read(spc)).value)}),
        }) }),
    };
    // The signature covers the attributes encoded as a SET; they travel as [0].
    const attr_set = try der.encodeSetOf(arena, &attrs);
    const signature = try rstd.crypto.rsa.signPkcs1v15(arena, key, Sha256, sha256Of(attr_set));
    const signer_attrs = try der.encode(arena, Tag.context(0), &.{(try der.read(attr_set)).value});

    const signer_info = try der.encode(arena, Tag.seq, &.{
        &.{ Tag.int, 1, 1 },
        try der.encode(arena, Tag.seq, &.{ cert.issuer, cert.serial }),
        sha256_alg,
        signer_attrs,
        try der.encode(arena, Tag.seq, &.{ der.Oid.rsa_encryption, &der.null_value }),
        try der.encode(arena, Tag.octets, &.{signature}),
    });
    const signed_data = try der.encode(arena, Tag.seq, &.{
        &.{ Tag.int, 1, 1 },
        try der.encode(arena, Tag.set, &.{sha256_alg}),
        try der.encode(arena, Tag.seq, &.{ oid_spc_indirect_data, try der.encode(arena, Tag.context(0), &.{spc}) }),
        try der.encode(arena, Tag.context(0), &.{cert.der}),
        try der.encode(arena, Tag.set, &.{signer_info}),
    });
    const pkcs7 = try der.encode(arena, Tag.seq, &.{ der.Oid.pkcs7_signed_data, try der.encode(arena, Tag.context(0), &.{signed_data}) });

    // WIN_CERTIFICATE: length, revision 2.0, WIN_CERT_TYPE_PKCS_SIGNED_DATA.
    const win_cert_len = 8 + pkcs7.len;
    const table_len = std.mem.alignForward(usize, win_cert_len, 8);
    const out = try arena.alloc(u8, padded.len + table_len);
    @memcpy(out[0..padded.len], padded);
    const wc = out[padded.len..];
    @memset(wc, 0);
    bytes.writeIntLE(u32, wc[0..], win_cert_len);
    bytes.writeIntLE(u16, wc[4..], 0x0200);
    bytes.writeIntLE(u16, wc[6..], 0x0002);
    @memcpy(wc[8..][0..pkcs7.len], pkcs7);
    bytes.writeIntLE(u32, out[pe.cert_dir..], padded.len);
    bytes.writeIntLE(u32, out[pe.cert_dir + 4 ..], table_len);
    return out;
}

/// Checks that `img`'s (first) signature covers it exactly and returns the
/// signer certificate's issuer Name as DER. Does not verify the RSA math or
/// the chain; firmware does that at boot.
pub fn signerIssuer(arena: Allocator, img: []const u8) ![]const u8 {
    const pe = try Pe.parse(arena, img);
    const at = bytes.readIntLE(u32, img[pe.cert_dir..]);
    if (bytes.readIntLE(u32, img[pe.cert_dir + 4 ..]) == 0) return error.NotSigned;
    if (img.len < @as(usize, at) + 8) return error.BadSignature;
    const wc_len = bytes.readIntLE(u32, img[at..]);
    if (bytes.readIntLE(u16, img[at + 6 ..]) != 0x0002 or img.len < @as(usize, at) + wc_len) return error.BadSignature;

    const content_info = try der.children(arena, (try (try der.read(img[at + 8 .. at + wc_len])).expect(Tag.seq)).value);
    if (content_info.len < 2) return error.BadSignature;
    const signed_data = try der.children(arena, (try (try der.read(content_info[1].value)).expect(Tag.seq)).value);
    if (signed_data.len < 4) return error.BadSignature;
    const encap = try der.children(arena, (try signed_data[2].expect(Tag.seq)).value);
    if (encap.len < 2) return error.BadSignature;
    const spc = try der.children(arena, (try (try der.read(encap[1].value)).expect(Tag.seq)).value);
    if (spc.len < 2) return error.BadSignature;
    const digest_info = try der.children(arena, (try spc[1].expect(Tag.seq)).value);
    if (digest_info.len < 2) return error.BadSignature;
    if (!std.mem.eql(u8, (try digest_info[1].expect(Tag.octets)).value, &try pe.digest(img))) return error.DigestMismatch;

    // signerInfos is the last element; issuerAndSerialNumber is its second.
    const signers = try der.children(arena, (try signed_data[signed_data.len - 1].expect(Tag.set)).value);
    if (signers.len < 1) return error.BadSignature;
    const signer = try der.children(arena, (try signers[0].expect(Tag.seq)).value);
    if (signer.len < 2) return error.BadSignature;
    const issuer_serial = try der.children(arena, (try signer[1].expect(Tag.seq)).value);
    if (issuer_serial.len < 1) return error.BadSignature;
    return (try issuer_serial[0].expect(Tag.seq)).all;
}

fn sha256Of(data: []const u8) [32]u8 {
    var d: [32]u8 = undefined;
    Sha256.hash(data, &d, .{});
    return d;
}
