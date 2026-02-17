HOGE_GLOBAL = 1

class Hoge:
    def __init__(self, name):
        self.name = name

    def greet(self):
        return f"Hello, {self.name}!"

def test_hoge():
    hoge = Hoge("Test")
    assert hoge.greet() == "Hello, Test!", "Hoge.greet() should return the correct greeting message."

if __name__ == "__main__":
    hoge  = Hoge("World")
    print(hoge.greet())
    print("This is a sandbox file for testing code snippets.")

    bracket = ((((((((2))))))))
