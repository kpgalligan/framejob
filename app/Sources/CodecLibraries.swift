import Foundation

/// The bundled encoders, SVT-AV1 and libvpx (road map "codec-export" C0, spec §11
/// CX-4): linked statically into every configuration from `build/codecs/`
/// (`tools/codecs/build_codecs.py`) and called through the bridging header, never an
/// `rc_*` export. C0 adds no export row; these reads prove the link, and
/// `-RCCodecProbe 1` prints them for `tools/proof/codecs_proof.py`.
enum CodecLibraries {
    static let argumentKey = "RCCodecProbe"

    /// SVT-AV1's own version string, e.g. "v4.2.0".
    static var svtAV1Version: String { String(cString: svt_av1_get_version()) }

    /// libvpx's own version string, e.g. "v1.17.0".
    static var vpxVersion: String { String(cString: vpx_codec_version_str()) }

    /// The VP9 encoder interface's name, e.g. "WebM Project VP9 Encoder v1.17.0".
    static var vp9EncoderName: String {
        String(cString: vpx_codec_iface_name(vpx_codec_vp9_cx()))
    }

    /// Opens an SVT-AV1 encoder handle with the library's defaults and closes it again:
    /// nil, or the sentence saying which step failed.
    static func openSVTAV1Handle() -> String? {
        var configuration = EbSvtAv1EncConfiguration()
        var handle: UnsafeMutablePointer<EbComponentType>?
        let opened = svt_av1_enc_init_handle(&handle, &configuration)
        guard opened == EB_ErrorNone, let handle else {
            return "svt_av1_enc_init_handle answered \(String(opened.rawValue, radix: 16))"
        }
        let closed = svt_av1_enc_deinit_handle(handle)
        guard closed == EB_ErrorNone else {
            return "svt_av1_enc_deinit_handle answered \(String(closed.rawValue, radix: 16))"
        }
        return nil
    }

    /// With `-RCCodecProbe` in the argument domain (and only there, as
    /// `AgentCatalogSnapshot.writeIfAsked` reads its own): prints
    /// `svt-av1 <version>` and `libvpx <version> (<VP9 encoder name>)` and exits 0, or
    /// one `framejob codec probe: <reason>` line on stderr and exits 1.
    static func probeIfAsked() {
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments[argumentKey] != nil else { return }
        if let failure = openSVTAV1Handle() {
            FileHandle.standardError.write(Data("framejob codec probe: \(failure)\n".utf8))
            exit(1)
        }
        let text = "svt-av1 \(svtAV1Version)\nlibvpx \(vpxVersion) (\(vp9EncoderName))\n"
        FileHandle.standardOutput.write(Data(text.utf8))
        exit(0)
    }
}
