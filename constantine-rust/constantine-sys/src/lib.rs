#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

#[cfg(target_pointer_width = "64")]
include!("bindings64.rs");
#[cfg(target_pointer_width = "32")]
include!("bindings32.rs");

impl std::fmt::Display for ctt_eth_bls_status {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let s = match self {
            ctt_eth_bls_status::cttEthBls_Success => "cttEthBls_Success",
            ctt_eth_bls_status::cttEthBls_VerificationFailure => "cttEthBls_VerificationFailure",
            ctt_eth_bls_status::cttEthBls_InputsLengthsMismatch => "cttEthBls_InputsLengthsMismatch",
            ctt_eth_bls_status::cttEthBls_ZeroLengthAggregation => "cttEthBls_ZeroLengthAggregation",
            ctt_eth_bls_status::cttEthBls_PointAtInfinity => "cttEthBls_PointAtInfinity",
        };
        write!(f, "{}", s)
    }
}

impl std::fmt::Display for ctt_codec_scalar_status {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let s = match self {
            ctt_codec_scalar_status::cttCodecScalar_Success => "cttCodecScalar_Success",
            ctt_codec_scalar_status::cttCodecScalar_Zero => "cttCodecScalar_Zero",
            ctt_codec_scalar_status::cttCodecScalar_ScalarLargerThanCurveOrder => "cttCodecScalar_ScalarLargerThanCurveOrder",
        };
        write!(f, "{}", s)
    }
}

impl std::fmt::Display for ctt_codec_ecc_status {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let s = match self {
            ctt_codec_ecc_status::cttCodecEcc_Success => "cttCodecEcc_Success",
            ctt_codec_ecc_status::cttCodecEcc_InvalidEncoding => "cttCodecEcc_Zero",
            ctt_codec_ecc_status::cttCodecEcc_CoordinateGreaterThanOrEqualModulus => "cttCodecEcc_CoordinateGreaterThanOrEqualModulus",
            ctt_codec_ecc_status::cttCodecEcc_PointNotOnCurve => "cttCodecEcc_PointNotOnCurve",
            ctt_codec_ecc_status::cttCodecEcc_PointNotInSubgroup => "cttCodecEcc_PointNotInSubgroup",
            ctt_codec_ecc_status::cttCodecEcc_PointAtInfinity => "cttCodecEcc_PointAtInfinity",
        };
        write!(f, "{}", s)
    }
}

impl std::fmt::Display for ctt_evm_status {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        let s = match self {
            ctt_evm_status::cttEVM_Success => "cttEVM_Success",
            ctt_evm_status::cttEVM_InvalidInputSize => "cttEVM_InvalidInputSize",
            ctt_evm_status::cttEVM_InvalidOutputSize => "cttEVM_InvalidOutputSize",
            ctt_evm_status::cttEVM_IntLargerThanModulus => "cttEVM_IntLargerThanModulus",
            ctt_evm_status::cttEVM_PointNotOnCurve => "cttEVM_PointNotOnCurve",
            ctt_evm_status::cttEVM_PointNotInSubgroup => "cttEVM_PointNotInSubgroup",
        };
        write!(f, "{}", s)
    }
}
