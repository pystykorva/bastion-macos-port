// NetworkOverview.swift - Re-export models from Models.swift for backward compat

import Foundation

// This file re-exports the types defined in Models.swift
// so they're available at the top-level Network namespace

public typealias NetworkOverview = BastionEngine.NetworkOverview
public typealias NetworkDevice = BastionEngine.NetworkDevice
public typealias NetworkConnection = BastionEngine.NetworkConnection
public typealias WiFiInfo = BastionEngine.WiFiInfo
public typealias WiFiNetwork = BastionEngine.WiFiNetwork
public typealias WiFiSurvey = BastionEngine.WiFiSurvey
public typealias WiFiRecommendation = BastionEngine.WiFiRecommendation
public typealias DNSStatus = BastionEngine.DNSStatus
public typealias ScanCheck = BastionEngine.ScanCheck
public typealias UPnPMapping = BastionEngine.UPnPMapping

