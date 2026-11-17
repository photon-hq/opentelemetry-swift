/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

@testable import PersistenceExporter
import XCTest

class OrchestratedFileReaderTests: XCTestCase {
  @UniqueTemporaryDirectory private var temporaryDirectory: Directory

  override func setUp() {
    super.setUp()
    temporaryDirectory.create()
  }

  override func tearDown() {
    temporaryDirectory.delete()
    super.tearDown()
  }

  func testItReadsSingleBatch() throws {
    let reader = OrchestratedFileReader(
      orchestrator: FilesOrchestrator(directory: temporaryDirectory,
                                      performance: StoragePerformanceMock.readAllFiles,
                                      dateProvider: SystemDateProvider())
    )
    _ = try temporaryDirectory
      .createFile(named: Date.mockAny().toFileName)
      .append(data: "ABCD".utf8Data)

    XCTAssertEqual(try temporaryDirectory.files().count, 1)
    let batch = reader.readNextBatch()

    XCTAssertEqual(batch?.data, "ABCD".utf8Data)
  }

  func testItMarksBatchesAsRead() throws {
    let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
    let reader = OrchestratedFileReader(
      orchestrator: FilesOrchestrator(directory: temporaryDirectory,
                                      performance: StoragePerformanceMock.readAllFiles,
                                      dateProvider: dateProvider)
    )
    let file1 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
    try file1.append(data: "1".utf8Data)

    let file2 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
    try file2.append(data: "2".utf8Data)

    let file3 = try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName)
    try file3.append(data: "3".utf8Data)

    var batch: Batch
    batch = try reader.readNextBatch().unwrapOrThrow()
    XCTAssertEqual(batch.data, "1".utf8Data)
    reader.markBatchAsRead(batch)

    batch = try reader.readNextBatch().unwrapOrThrow()
    XCTAssertEqual(batch.data, "2".utf8Data)
    reader.markBatchAsRead(batch)

    batch = try reader.readNextBatch().unwrapOrThrow()
    XCTAssertEqual(batch.data, "3".utf8Data)
    reader.markBatchAsRead(batch)

    XCTAssertNil(reader.readNextBatch())
    XCTAssertEqual(try temporaryDirectory.files().count, 0)
    XCTAssertTrue(reader.undeletedFileNames.isEmpty)
  }

  func testItDoesNotRetainDeletedFiles() throws {
    let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
    let reader = OrchestratedFileReader(
      orchestrator: FilesOrchestrator(directory: temporaryDirectory,
                                      performance: StoragePerformanceMock.readAllFiles,
                                      dateProvider: dateProvider)
    )

    for index in 0 ..< 100 {
      try temporaryDirectory
        .createFile(named: dateProvider.currentDate().toFileName)
        .append(data: "\(index)".utf8Data)
      let batch = try reader.readNextBatch().unwrapOrThrow()
      XCTAssertEqual(batch.data, "\(index)".utf8Data)
      reader.markBatchAsRead(batch)
    }

    XCTAssertEqual(try temporaryDirectory.files().count, 0)
    XCTAssertTrue(reader.undeletedFileNames.isEmpty)
  }

  func testItSkipsFilesThatCouldNotBeDeleted() throws {
    let dateProvider = RelativeDateProvider(advancingBySeconds: 60)
    let reader = OrchestratedFileReader(
      orchestrator: FilesOrchestrator(directory: temporaryDirectory,
                                      performance: StoragePerformanceMock.readAllFiles,
                                      dateProvider: dateProvider)
    )
    try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName).append(data: "1".utf8Data)
    try temporaryDirectory.createFile(named: dateProvider.currentDate().toFileName).append(data: "2".utf8Data)

    let batch = try reader.readNextBatch().unwrapOrThrow()
    XCTAssertEqual(batch.data, "1".utf8Data)
    reader.markBatchAsRead(Batch(data: batch.data, file: UndeletableFile(name: batch.file.name)))

    XCTAssertEqual(reader.undeletedFileNames, [batch.file.name])
    XCTAssertEqual(try reader.readNextBatch().unwrapOrThrow().data, "2".utf8Data)
  }
}

private struct UndeletableFile: ReadableFile {
  let name: String

  func read() throws -> Data { Data() }

  func delete() throws {
    throw CocoaError(.fileWriteNoPermission)
  }
}
