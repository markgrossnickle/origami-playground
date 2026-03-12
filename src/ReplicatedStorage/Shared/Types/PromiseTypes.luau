--!strict

export type Promise<T> = {
	andThen: <U>(self: Promise<T>, (T) -> U | Promise<U>) -> Promise<U>,
	catch: (self: Promise<T>, (any) -> any) -> Promise<T>,
	finally: (self: Promise<T>, () -> ()) -> Promise<T>,
	cancel: (self: Promise<T>) -> (),
}

return {}
