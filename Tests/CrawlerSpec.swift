import Nimble
import Quick
import Swindler
@testable import x3

class CrawlerSpec: QuickSpec {
    override func spec() {
        var fakeApp: FakeApplication!
        var a, b, c, d, e: FakeWindow!

        func setup(screens: [FakeScreen]) {
            fakeApp = FakeApplication(parent: FakeState(screens: screens))
            a = createWindowForApp(fakeApp, "A")
            b = createWindowForApp(fakeApp, "B")
            c = createWindowForApp(fakeApp, "C")
            d = createWindowForApp(fakeApp, "D")
            e = createWindowForApp(fakeApp, "E")
        }

        context("with a single screen") {
            var tree: Tree!
            var root: ContainerNode { get { return tree.root } }

            beforeEach {
                let screen = FakeScreen()
                setup(screens: [screen])
                tree = Tree(screen: screen.screen)
            }

            describe("Crawler") {
                func checkMove(_ direction: Direction, leaf: Crawler.DescentStrategy,
                               from: FakeWindow, to: FakeWindow,
                               file: String = #file, line: UInt = #line) {
                    let crawler = Crawler(at: root.find(window: from.window)!)
                    let result = crawler.move(direction, leaf: leaf)?.node
                    expect(result, file: file, line: line).to(equal(
                        root.find(window: to.window)!.kind
                    ))
                }

                var child, grandchild: ContainerNode!
                beforeEach {
                    root.makeWindow(a.window, at: .end)
                        .makeContainer(layout: .vertical, at: .end) { n in
                            child = n
                            n.makeWindow(b.window, at: .end)
                             .makeWindow(c.window, at: .end)
                             .makeContainer(layout: .horizontal, at: .end) { n in
                                 grandchild = n
                                 n.makeWindow(d.window, at: .end)
                                  .makeWindow(e.window, at: .end)
                             }
                        }
                }

                it("moves predictably") {
                    checkMove(.right, leaf: .selected, from: d, to: e)
                    checkMove(.up,    leaf: .selected, from: d, to: c)
                    checkMove(.left,  leaf: .selected, from: d, to: a)
                }

                it("follows selection path when DescentStrategy.selected is used") {
                    root.find(window: e.window)!.selectGlobally()
                    checkMove(.right, leaf: .selected, from: a, to: e)
                    root.find(window: c.window)!.selectGlobally()
                    checkMove(.right, leaf: .selected, from: a, to: c)
                }

                it("ascends") {
                    var crawl = Crawler(at: root.find(window: d.window)!)
                    crawl = crawl.ascend()!
                    expect(crawl.node) == grandchild.kind
                    crawl = crawl.ascend()!
                    expect(crawl.node) == child.kind
                    crawl = crawl.ascend()!
                    expect(crawl.node) == root.kind
                }

                it("doesn't move from the root node") {
                    let crawl = Crawler(at: root.kind)
                    expect(crawl.move(.down, leaf: .selected)?.node).to(beNil())
                }
            }
        }
    }
}
