# all tf files will process at the same time within the directory

resource "aws_vpc" "lunx_vpc" {
  cidr_block           = "10.123.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "lunx_dev_env"
  }
}
# run terraform plan to see configurations
# then run terraform apply - yes

# lunx public subnet
resource "aws_subnet" "lunx_public_subnet" {
  vpc_id                  = aws_vpc.lunx_vpc.id
  cidr_block              = "10.123.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2a"

  tags = {
    Name = "lunx-dev-public"
  }
}

# lunx internet gateway (igw)
resource "aws_internet_gateway" "lunx_internet_gateway" {
  vpc_id = aws_vpc.lunx_vpc.id

  tags = {
    Name = "lunx_dev_igw"
  }
}

# lunx route table
resource "aws_route_table" "lunx_public_rt" {
  vpc_id = aws_vpc.lunx_vpc.id

  tags = {
    Name = "lunx_public_rt"
  }
}

# lunx default route
resource "aws_route" "lunx_default_route" {
  route_table_id         = aws_route_table.lunx_public_rt.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lunx_internet_gateway.id
}

# lunx route table assoiciation
resource "aws_route_table_association" "lunx_public_assoc" {
  subnet_id      = aws_subnet.lunx_public_subnet.id
  route_table_id = aws_route_table.lunx_public_rt.id
}

# lunx security groups
resource "aws_security_group" "lunx_sg" {
  name        = "lunx_dev_sg"
  description = "lunx security group for development environment"
  vpc_id      = aws_vpc.lunx_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# aws resource key pair
resource "aws_key_pair" "lunx_auth" {
  key_name   = "lunxkey"
  public_key = file("~/.ssh/lunxkey.pub")
}

# aws ec2 instance
resource "aws_instance" "lunx_dev_node" {
  instance_type          = "t2.micro"
  ami                    = data.aws_ami.server_ami.id
  key_name               = aws_key_pair.lunx_auth.id
  vpc_security_group_ids = [aws_security_group.lunx_sg.id]
  subnet_id              = aws_subnet.lunx_public_subnet.id
  # userdata for bootstrapping the ec2 instance
  user_data = file("userdata.tpl")
  # resize the default size of the volume
  root_block_device {
    volume_size = 10
  }

  tags = {
    Name = "lunx-dev-node"
  }

  # used as a last resort, not ideal for remote instances, use orchestration tools instead.
  # provisioner ALSO does not affect the terraform state, no changes will be shown after running terraform plan
  provisioner "local-exec" {
    # not dynamic -- "linux-ssh-config.tpl", use variables
    command = templatefile("${var.host_os}-ssh-config.tpl", {
      hostname     = self.public_ip
      user         = "ubuntu"
      identityfile = "~/.ssh/lunxkey"
    })

    # interpreter for linux or mac
    # the old way - - (not dynamic)interpreter = ["bash", "-c"]
    # for windows use: interpreter = ["Powershell", "Command"]
    # dynamic way using variables
    interpreter = var.host_os == "windows" ? ["Powershell", "-Command"] : ["bash", "-c"]
  }

}