### You need to have locally downloaded UBUNTU images before (not interesting to commit those 5 GB file in github...)

k8sgui : https://drive.google.com/file/d/1hWm12deQDGXaGtEXHdNizWv6JW4fEKe0/view?usp=sharing
k8s : https://drive.google.com/file/d/1O9gVBEvuYVmTQzHu8ujvzR0jlYYtt0cX/view?usp=sharing



### Then convert ova image in .tar and use any archive tool to extract only .vmdk files

You should have in your local folder : 
k8s-disk001.vmdk
k8sgui-disk001.vmdk



TODO : store vmdk files in google cloud drive then use http provider from terraform to download them before upload to s3
https://registry.terraform.io/providers/hashicorp/http/latest/docs/data-sources/http

Not sure it is worth the effort, so still TODO