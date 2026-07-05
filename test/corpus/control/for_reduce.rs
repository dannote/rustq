fn validate(values: Vec<u32>) -> NifResult<()> {
    {
        let mut __rustq_reduce = Ok(());
        for value in values {
            __rustq_reduce = match __rustq_reduce {
                Ok(()) => {
                    if value == 0 {
                        Err(rustler::Error::BadArg)
                    } else {
                        Ok(())
                    }
                }
                __rustq_reduce_value => __rustq_reduce_value,
            };
        }
        __rustq_reduce
    }
}
