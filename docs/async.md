# Asynchronous serialization/deserialization

Asynchronous serialization can be achieved through [overloading](/docs/overloading.md#2-custom-preprocess) `ldump.serializer`: each value node is passed through it, so it's possible to insert a conditional `coroutine.yield()` there. The resulting asynchronicity seems to be stable.

Asynchronous deserialization can be achieved also through `ldump.serializer`, but by inserting `coroutine.yield()`s into some of the returned functions.

You can look up my implementation in the kernel of the [fallen engine](https://github.com/girvel/engine); its implementation of the deserialization is a bit rough, but it has a room for improvement.
